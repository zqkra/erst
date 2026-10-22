//! Replays a recorded thumbnail trace through candidate keep policies.
//!
//! `ErstProbe` writes the trace with `--trace <file>`. The format is one header
//! and then one fixed-size record per captured thumbnail:
//!
//! ```text
//! header: "ERSTTRE1" (8 bytes), width (u32 LE), height (u32 LE)
//! record: captured_at_ms (i64 LE), focus_changed (u8), luma (width * height bytes)
//! ```
//!
//! Run with `cargo run --release -p erst-core --example replay_keep -- <trace>`.
//! The tool reports kept frames, the keep rate, the longest gap between kept
//! frames, and the decision reasons, for the legacy policy and for candidate
//! threshold sets. It also reports how late each frame the legacy policy kept
//! is recorded by the candidate, and how quickly each stable page change is
//! recorded, because a real change of screen must still be kept, even when it
//! lands a few seconds late.

#![allow(
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::cast_precision_loss
)]

use std::collections::BTreeMap;
use std::error::Error;
use std::fs;
use std::io::{Error as IoError, ErrorKind};

use erst_core::{FrameContext, KeepPolicy, KeepReason, KeepState, Thumbnail};

/// Marks the trace format version.
const MAGIC: &[u8; 8] = b"ERSTTRE1";
/// Magic (8 bytes) plus width and height (4 bytes each).
const HEADER_BYTES: usize = 16;
/// Largest thumbnail edge accepted from a trace.
const MAX_THUMBNAIL_EDGE: u32 = 4_096;
/// A legacy kept frame delayed further than this is worth a look, in ms.
const LAG_ALERT_MS: i64 = 20_000;
/// Changed tile fraction that marks a new page, independent of a candidate policy.
const PAGE_CHANGE_RATIO: f32 = 0.08;
/// Page changes shown one by one when they are recorded too late.
const SLOW_PAGE_CHANGES: usize = 5;
/// Every keep reason, in the order the histogram prints them.
const REASONS: [KeepReason; 8] = [
    KeepReason::FirstFrame,
    KeepReason::FocusChanged,
    KeepReason::MaxGap,
    KeepReason::MajorChanged,
    KeepReason::Changed,
    KeepReason::MinorDeferred,
    KeepReason::MotionThrottled,
    KeepReason::Unchanged,
];

fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: replay_keep <trace file>");
        std::process::exit(2);
    });
    let frames = read_trace(&path)?;
    let Some(first) = frames.first() else {
        println!("{path}: no frames");
        return Ok(());
    };
    let duration_ms = frames.last().map_or(0, |frame| frame.now_ms - first.now_ms);
    let focus_changes = frames.iter().filter(|frame| frame.focus_changed).count();
    println!(
        "trace {path}: {} frames over {:.1} s, {focus_changes} focus changes",
        frames.len(),
        ms_to_seconds(duration_ms)
    );
    println!();

    let page_changes = stable_page_changes(&frames);
    println!("stable page changes: {}", page_changes.len());
    println!();

    let legacy = legacy_policy();
    let legacy_outcome = replay(&legacy, &frames);
    print_outcome("legacy", "keep_ratio 0.005, no deferral", &legacy_outcome);
    println!();

    for (name, policy) in candidates() {
        let outcome = replay(&policy, &frames);
        let lag = lag_behind(&legacy_outcome.kept_indexes, &outcome.kept_indexes, &frames);
        print_outcome(name, &describe(&policy), &outcome);
        print_lag(&lag, &policy);
        print_page_changes(&page_changes, &outcome, &frames, &policy);
        println!();
    }
    Ok(())
}

/// Indexes of captured frames that start a new stable view.
///
/// A page change is a frame that differs from the previous one by at least
/// `PAGE_CHANGE_RATIO` while the next frame stays close to it. Video and other
/// continuous motion never settle, so their frames are not counted. The
/// `PAGE_CHANGE_RATIO` is fixed so every policy is measured against the same
/// events, even when it raises `major_ratio`.
fn stable_page_changes(frames: &[Frame]) -> Vec<usize> {
    let detector = KeepPolicy {
        major_ratio: PAGE_CHANGE_RATIO,
        ..KeepPolicy::default()
    };
    let mut changes = Vec::new();
    for index in 1..frames.len() {
        let arrived = detector.change_ratio(&frames[index - 1].thumbnail, &frames[index].thumbnail);
        if arrived < PAGE_CHANGE_RATIO {
            continue;
        }
        let settled = frames.get(index + 1).is_none_or(|next| {
            detector.change_ratio(&frames[index].thumbnail, &next.thumbnail) < PAGE_CHANGE_RATIO
        });
        if settled {
            changes.push(index);
        }
    }
    changes
}

/// How quickly a policy records each stable page change.
fn print_page_changes(
    page_changes: &[usize],
    outcome: &Outcome,
    frames: &[Frame],
    policy: &KeepPolicy,
) {
    let mut delays = Vec::with_capacity(page_changes.len());
    for index in page_changes {
        let first = outcome.kept_indexes.partition_point(|kept| kept < index);
        if let Some(kept) = outcome.kept_indexes.get(first) {
            delays.push((*index, frames[*kept].now_ms - frames[*index].now_ms));
        }
    }
    let within_minor_gap = delays
        .iter()
        .filter(|(_, delay)| *delay <= policy.minor_gap_ms)
        .count();
    let worst = delays.iter().map(|(_, delay)| *delay).max().unwrap_or(0);
    println!(
        "  page changes: {within_minor_gap} of {} within the minor gap, worst {:.1} s",
        page_changes.len(),
        ms_to_seconds(worst)
    );
    let mut late: Vec<(usize, i64)> = delays
        .into_iter()
        .filter(|(_, delay)| *delay > policy.motion_gap_ms.max(policy.minor_gap_ms))
        .collect();
    late.sort_by_key(|(_, delay)| std::cmp::Reverse(*delay));
    for (index, delay) in late.into_iter().take(SLOW_PAGE_CHANGES) {
        println!(
            "    page change at {:.1} s recorded {:.1} s late",
            ms_to_seconds(frames[index].now_ms - frames[0].now_ms),
            ms_to_seconds(delay)
        );
    }
}

/// One thumbnail as the probe captured it.
struct Frame {
    now_ms: i64,
    focus_changed: bool,
    thumbnail: Thumbnail,
}

fn read_trace(path: &str) -> Result<Vec<Frame>, Box<dyn Error>> {
    let bytes = fs::read(path)?;
    if bytes.len() < HEADER_BYTES || &bytes[0..8] != MAGIC {
        return Err(invalid(format!("{path} is not an ERSTTRE1 trace")));
    }
    let width = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);
    let height = u32::from_le_bytes([bytes[12], bytes[13], bytes[14], bytes[15]]);
    if width == 0 || height == 0 || width > MAX_THUMBNAIL_EDGE || height > MAX_THUMBNAIL_EDGE {
        return Err(invalid(format!("{path} carries {width}x{height}")));
    }
    let pixels = usize::try_from(u64::from(width) * u64::from(height))?;
    let record_bytes = 8 + 1 + pixels;
    let mut frames = Vec::with_capacity(bytes.len() / record_bytes);
    for record in bytes[HEADER_BYTES..].chunks_exact(record_bytes) {
        let now_ms = i64::from_le_bytes([
            record[0], record[1], record[2], record[3], record[4], record[5], record[6], record[7],
        ]);
        let focus_changed = record[8] != 0;
        let thumbnail = Thumbnail::new(width, height, record[9..].to_vec())?;
        frames.push(Frame {
            now_ms,
            focus_changed,
            thumbnail,
        });
    }
    Ok(frames)
}

/// The policy this change replaces: no major ratio, no gaps.
fn legacy_policy() -> KeepPolicy {
    KeepPolicy {
        // No tile ratio can reach this, so every change is minor and kept.
        major_ratio: f32::MAX,
        minor_gap_ms: 0,
        ..KeepPolicy::default()
    }
}

/// Threshold sets to compare against the legacy policy.
///
/// The motion gap moves kept frames the most on a motion-heavy trace, so it is
/// swept first. The major ratio and the minor gap only steer minor edits.
fn candidates() -> Vec<(&'static str, KeepPolicy)> {
    let base = KeepPolicy::default();
    vec![
        (
            "start",
            KeepPolicy {
                major_ratio: 0.08,
                minor_gap_ms: 20_000,
                motion_gap_ms: 10_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
        (
            "fast-motion",
            KeepPolicy {
                major_ratio: 0.08,
                minor_gap_ms: 20_000,
                motion_gap_ms: 5_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
        (
            "slow-motion",
            KeepPolicy {
                major_ratio: 0.08,
                minor_gap_ms: 20_000,
                motion_gap_ms: 20_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
        (
            "calm",
            KeepPolicy {
                major_ratio: 0.08,
                minor_gap_ms: 30_000,
                motion_gap_ms: 15_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
        (
            "steady",
            KeepPolicy {
                major_ratio: 0.10,
                minor_gap_ms: 25_000,
                motion_gap_ms: 12_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
        (
            "tight",
            KeepPolicy {
                major_ratio: 0.06,
                minor_gap_ms: 15_000,
                motion_gap_ms: 10_000,
                motion_run_keeps: 3,
                ..base
            },
        ),
    ]
}

/// What one policy did with the whole trace.
struct Outcome {
    kept_indexes: Vec<usize>,
    reasons: BTreeMap<&'static str, usize>,
    longest_gap_ms: i64,
}

fn replay(policy: &KeepPolicy, frames: &[Frame]) -> Outcome {
    let mut last_kept: Option<(&Thumbnail, i64)> = None;
    let mut state = KeepState::default();
    let mut kept_indexes = Vec::new();
    let mut reasons = BTreeMap::new();
    let mut longest_gap_ms = 0_i64;
    for (index, frame) in frames.iter().enumerate() {
        let decision = policy.decide(
            last_kept.map(|(thumbnail, _)| thumbnail),
            &frame.thumbnail,
            &FrameContext {
                now_ms: frame.now_ms,
                last_kept_ms: last_kept.map(|(_, at_ms)| at_ms),
                focus_changed: frame.focus_changed,
            },
            state,
        );
        state = decision.next_state;
        *reasons.entry(reason_name(decision.reason)).or_insert(0) += 1;
        if !decision.keep {
            continue;
        }
        if let Some((_, at_ms)) = last_kept {
            longest_gap_ms = longest_gap_ms.max(frame.now_ms - at_ms);
        }
        last_kept = Some((&frame.thumbnail, frame.now_ms));
        kept_indexes.push(index);
    }
    Outcome {
        kept_indexes,
        reasons,
        longest_gap_ms,
    }
}

/// One line per policy with the numbers the thresholds are tuned against.
fn print_outcome(name: &str, description: &str, outcome: &Outcome) {
    let frames = outcome.reasons.values().sum::<usize>();
    let kept = outcome.kept_indexes.len();
    println!("{name}: {description}");
    println!(
        "  kept {kept} of {frames} ({:.1}%), longest gap {:.1} s",
        percent(kept, frames),
        ms_to_seconds(outcome.longest_gap_ms)
    );
    println!("  kept because: {}", histogram(&outcome.reasons, true));
    println!("  skipped because: {}", histogram(&outcome.reasons, false));
}

/// The counted reasons on one side of the keep decision, in policy order.
fn histogram(reasons: &BTreeMap<&'static str, usize>, kept: bool) -> String {
    let counted = REASONS
        .iter()
        .filter(|reason| is_keep(**reason) == kept)
        .filter_map(|reason| {
            let count = reasons.get(reason_name(*reason)).copied()?;
            (count > 0).then(|| format!("{} {count}", reason_name(*reason)))
        })
        .collect::<Vec<_>>();
    if counted.is_empty() {
        "none".to_owned()
    } else {
        counted.join(", ")
    }
}

fn is_keep(reason: KeepReason) -> bool {
    matches!(
        reason,
        KeepReason::FirstFrame
            | KeepReason::FocusChanged
            | KeepReason::MaxGap
            | KeepReason::MajorChanged
            | KeepReason::Changed
    )
}

/// How late the candidate records each frame the legacy policy kept.
fn lag_behind(
    legacy_indexes: &[usize],
    candidate_indexes: &[usize],
    frames: &[Frame],
) -> Vec<(usize, i64)> {
    legacy_indexes
        .iter()
        .filter_map(|index| {
            let kept = candidate_indexes.partition_point(|candidate| candidate < index);
            let reached = *candidate_indexes
                .get(kept)
                .or_else(|| candidate_indexes.last())?;
            Some((*index, frames[reached].now_ms - frames[*index].now_ms))
        })
        .collect()
}

fn print_lag(lag: &[(usize, i64)], policy: &KeepPolicy) {
    let worst = lag.iter().map(|(_, delay)| *delay).max().unwrap_or(0);
    let beyond_minor_gap = lag
        .iter()
        .filter(|(_, delay)| *delay > policy.minor_gap_ms)
        .count();
    let beyond_alert = lag
        .iter()
        .filter(|(_, delay)| *delay > LAG_ALERT_MS)
        .count();
    println!(
        "  lag behind legacy keeps: max {:.1} s, {beyond_minor_gap} beyond the minor gap, {beyond_alert} beyond {:.0} s",
        ms_to_seconds(worst),
        ms_to_seconds(LAG_ALERT_MS)
    );
}

fn describe(policy: &KeepPolicy) -> String {
    format!(
        "major {:.2}, minor gap {:.0} s, motion gap {:.0} s, run {}",
        policy.major_ratio,
        ms_to_seconds(policy.minor_gap_ms),
        ms_to_seconds(policy.motion_gap_ms),
        policy.motion_run_keeps
    )
}

fn reason_name(reason: KeepReason) -> &'static str {
    match reason {
        KeepReason::FirstFrame => "FirstFrame",
        KeepReason::FocusChanged => "FocusChanged",
        KeepReason::MaxGap => "MaxGap",
        KeepReason::MajorChanged => "MajorChanged",
        KeepReason::Changed => "Changed",
        KeepReason::MinorDeferred => "MinorDeferred",
        KeepReason::MotionThrottled => "MotionThrottled",
        KeepReason::Unchanged => "Unchanged",
    }
}

fn percent(part: usize, whole: usize) -> f64 {
    if whole == 0 {
        return 0.0;
    }
    part as f64 / whole as f64 * 100.0
}

fn ms_to_seconds(value: i64) -> f64 {
    value as f64 / 1000.0
}

fn invalid(message: String) -> Box<dyn Error> {
    IoError::new(ErrorKind::InvalidData, message).into()
}
