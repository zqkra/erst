//! Keep policy behavior while the screen shows continuous motion.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use super::super::{KeepDecision, KeepPolicy, KeepReason, KeepState, Thumbnail};
use super::{context, major_change, policy, thumbnail, thumbnail_with_changed_tiles};

/// Runs `(now_ms, thumbnail)` frames through the default policy, keeping the
/// real last kept frame, and returns each time with its decision.
fn replay(frames: impl IntoIterator<Item = (i64, Thumbnail)>) -> Vec<(i64, KeepDecision)> {
    let policy = policy();
    let mut last_kept: Option<(Thumbnail, i64)> = None;
    let mut state = KeepState::default();
    let mut decisions = Vec::new();
    for (now_ms, next) in frames {
        let decision = policy.decide(
            last_kept.as_ref().map(|(thumbnail, _)| thumbnail),
            &next,
            &context(now_ms, last_kept.as_ref().map(|(_, at)| *at), false),
            state,
        );
        state = decision.next_state;
        if decision.keep {
            last_kept = Some((next, now_ms));
        }
        decisions.push((now_ms, decision));
    }
    decisions
}

/// Times of the frames a replay kept.
fn kept_times(decisions: &[(i64, KeepDecision)]) -> Vec<i64> {
    decisions
        .iter()
        .filter(|(_, decision)| decision.keep)
        .map(|(at, _)| *at)
        .collect()
}

/// What a video shows at whole second `second`.
///
/// The picture changes every two seconds and holds in between, so an unchanged
/// frame sits between every two majors.
fn video_fill(second: i64) -> u8 {
    let scene = second / 2;
    if scene % 2 == 1 { 200 } else { 0 }
}

fn fills(fills: &[u8], step_ms: i64) -> Vec<(i64, Thumbnail)> {
    fills
        .iter()
        .enumerate()
        .map(|(index, fill)| {
            let now_ms = i64::try_from(index).unwrap() * step_ms;
            (now_ms, thumbnail(160, 90, *fill))
        })
        .collect()
}

#[test]
fn throttles_continuous_motion_to_the_motion_gap() {
    let decisions = replay(fills(&[0, 200, 100, 20, 180, 60, 220, 90, 240], 2_000));
    let reasons: Vec<KeepReason> = decisions
        .iter()
        .map(|(_, decision)| decision.reason)
        .collect();
    assert_eq!(reasons[0], KeepReason::FirstFrame);
    // Three quick major keeps start the motion run at 6 s. Every frame until the
    // motion gap has passed since that keep is throttled.
    assert_eq!(reasons[1], KeepReason::MajorChanged);
    assert_eq!(reasons[2], KeepReason::MajorChanged);
    assert_eq!(reasons[3], KeepReason::MajorChanged);
    assert_eq!(reasons[4], KeepReason::MotionThrottled);
    assert_eq!(reasons[5], KeepReason::MotionThrottled);
    assert_eq!(reasons[6], KeepReason::MotionThrottled);
    assert_eq!(reasons[7], KeepReason::MotionThrottled);
    // Ten seconds after the last kept frame the throttle opens again.
    assert_eq!(reasons[8], KeepReason::MajorChanged);
}

#[test]
fn a_video_is_throttled_to_the_motion_gap_through_quiet_frames() {
    let decisions =
        replay((0..=60).map(|second| (second * 1_000, thumbnail(160, 90, video_fill(second)))));
    let kept = kept_times(&decisions);
    let policy = KeepPolicy::default();
    let quick_keeps = usize::from(policy.motion_run_keeps);
    assert!(
        kept.len() <= quick_keeps + 6,
        "kept {} frames at {kept:?}",
        kept.len()
    );
    for pair in kept[quick_keeps..].windows(2) {
        assert!(
            pair[1] - pair[0] >= policy.motion_gap_ms,
            "keeps {} ms apart at {kept:?}",
            pair[1] - pair[0]
        );
    }
    // The quiet frames inside the first run carry the run instead of resetting
    // it, which is what lets the throttle engage at all.
    let (_, quiet) = decisions.iter().find(|(at, _)| *at == 3_000).unwrap();
    assert_eq!(quiet.reason, KeepReason::Unchanged);
    assert_eq!(quiet.next_state.major_run, 1);
    assert_eq!(quiet.next_state.last_major_ms, Some(2_000));
    assert!(
        decisions
            .iter()
            .any(|(_, decision)| decision.reason == KeepReason::MotionThrottled)
    );
}

#[test]
fn a_pause_longer_than_the_motion_gap_ends_motion() {
    let mut frames = vec![
        (0, thumbnail(160, 90, 0)),
        (2_000, thumbnail(160, 90, 200)),
        (4_000, thumbnail(160, 90, 0)),
        (6_000, thumbnail(160, 90, 200)),
    ];
    // Fifteen seconds with no major change while the picture holds.
    for second in 7..=21 {
        frames.push((second * 1_000, thumbnail(160, 90, 200)));
    }
    frames.push((22_000, thumbnail(160, 90, 0)));
    let decisions = replay(frames);
    let (_, quiet) = &decisions[18];
    assert_eq!(quiet.reason, KeepReason::Unchanged);
    assert_eq!(quiet.next_state.major_run, 3);
    assert_eq!(quiet.next_state.last_major_ms, Some(6_000));
    let (at, major) = &decisions[19];
    assert_eq!(*at, 22_000);
    assert!(major.keep);
    assert_eq!(major.reason, KeepReason::MajorChanged);
    assert_eq!(major.next_state.major_run, 1);
    assert_eq!(major.next_state.last_major_ms, Some(22_000));
}

#[test]
fn a_minor_change_carries_the_motion_run() {
    let frames = vec![
        (0, thumbnail(160, 90, 200)),
        (2_000, thumbnail(160, 90, 0)),
        (4_000, thumbnail(160, 90, 200)),
        (6_000, thumbnail(160, 90, 0)),
        (26_000, thumbnail_with_changed_tiles(1)),
        (28_000, thumbnail(160, 90, 200)),
    ];
    let decisions = replay(frames);
    // A minor change 20 s later is kept and leaves the run alone.
    let (_, minor) = &decisions[4];
    assert!(minor.keep);
    assert_eq!(minor.reason, KeepReason::Changed);
    assert_eq!(minor.next_state.major_run, 3);
    assert_eq!(minor.next_state.last_major_ms, Some(6_000));
    // The next major is more than a motion gap after the last major change, so
    // a new run starts and the frame is kept at once.
    let (_, major) = &decisions[5];
    assert!(major.keep);
    assert_eq!(major.reason, KeepReason::MajorChanged);
    assert_eq!(major.next_state.major_run, 1);
}

#[test]
fn motion_keeps_the_run_alive_while_it_is_throttled() {
    let policy = policy();
    let previous = major_change();
    let next = thumbnail(160, 90, 0);
    let skipped = policy.decide(
        Some(&previous),
        &next,
        &context(8_000, Some(6_000), false),
        KeepState {
            major_run: 3,
            last_major_ms: Some(6_000),
        },
    );
    assert!(!skipped.keep);
    assert_eq!(skipped.reason, KeepReason::MotionThrottled);
    assert_eq!(skipped.next_state.major_run, 4);
    assert_eq!(skipped.next_state.last_major_ms, Some(8_000));
    let kept = policy.decide(
        Some(&previous),
        &next,
        &context(16_000, Some(6_000), false),
        skipped.next_state,
    );
    assert!(kept.keep);
    assert_eq!(kept.reason, KeepReason::MajorChanged);
    assert_eq!(kept.next_state.major_run, 5);
    assert_eq!(kept.next_state.last_major_ms, Some(16_000));
}

#[test]
fn a_major_change_after_a_long_pause_starts_a_new_run() {
    let previous = major_change();
    let next = thumbnail(160, 90, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(60_000, Some(0), false),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::MajorChanged);
    assert_eq!(decision.next_state.major_run, 1);
    assert_eq!(decision.next_state.last_major_ms, Some(60_000));
}

#[test]
fn focus_change_passes_during_motion_and_ends_the_run() {
    let previous = major_change();
    let next = thumbnail(160, 90, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(4_000, Some(2_000), true),
        KeepState {
            major_run: 5,
            last_major_ms: Some(2_000),
        },
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::FocusChanged);
    assert_eq!(decision.next_state, KeepState::default());
}

#[test]
fn max_gap_passes_during_motion() {
    let previous = major_change();
    let next = thumbnail(160, 90, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(300_000, Some(0), false),
        KeepState {
            major_run: 5,
            last_major_ms: Some(2_000),
        },
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::MaxGap);
    assert_eq!(decision.next_state, KeepState::default());
}

#[test]
fn zero_motion_run_behaves_like_one() {
    let previous = major_change();
    let next = thumbnail(160, 90, 0);
    let policy = KeepPolicy {
        motion_run_keeps: 0,
        ..policy()
    };
    let decision = policy.decide(
        Some(&previous),
        &next,
        &context(4_000, Some(2_000), false),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::MajorChanged);
}
