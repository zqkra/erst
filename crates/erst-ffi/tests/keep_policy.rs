//! The keep policy as `Engine.evaluate_frame` applies it.
//!
//! Every case is driven by explicit capture times, so no test sleeps.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::open_engine;
use erst_ffi::{FfiKeepReason, FfiThumbnail};

const WIDTH: u32 = 160;
const HEIGHT: u32 = 90;

/// Rows at the top of a thumbnail that the default policy ignores.
const IGNORED_ROWS: usize = 3;

/// Quick major keeps the default policy allows before it throttles motion.
const MOTION_RUN_KEEPS: usize = 3;

/// Gap between keeps while the screen shows continuous motion.
const MOTION_GAP_MS: i64 = 10_000;

/// One 160x90 thumbnail of a single luma value.
fn thumbnail(fill: u8) -> FfiThumbnail {
    ffi_thumbnail(vec![fill; usize::try_from(WIDTH * HEIGHT).unwrap()])
}

fn ffi_thumbnail(luma: Vec<u8>) -> FfiThumbnail {
    FfiThumbnail {
        width: WIDTH,
        height: HEIGHT,
        luma,
    }
}

/// `base` with the first compared tile brightened: one changed tile of 144, a
/// minor change that is above the keep ratio and below the major ratio.
fn minor_change(base: u8) -> FfiThumbnail {
    changed_tiles(base, 1)
}

/// `base` with the first `count` tiles of the compared grid brightened.
fn changed_tiles(base: u8, count: usize) -> FfiThumbnail {
    let mut luma = vec![base; usize::try_from(WIDTH * HEIGHT).unwrap()];
    let width = usize::try_from(WIDTH).unwrap();
    for row in IGNORED_ROWS..IGNORED_ROWS + 10 {
        for column in 0..count * 10 {
            luma[row * width + column] = 200;
        }
    }
    ffi_thumbnail(luma)
}

/// What a video shows at whole second `second`: a new picture every two
/// seconds, held in between.
fn video_fill(second: usize) -> u8 {
    let scene = second / 2;
    if scene % 2 == 1 { 200 } else { 0 }
}

#[test]
fn skips_a_minor_change_until_the_minor_gap() {
    let (_temp, _data_dir, engine) = open_engine();
    assert_eq!(
        engine.evaluate_frame(thumbnail(0), 0, false).reason,
        FfiKeepReason::FirstFrame
    );

    let change = minor_change(0);
    let deferred = engine.evaluate_frame(change.clone(), 2_000, false);
    assert!(!deferred.keep);
    assert_eq!(deferred.reason, FfiKeepReason::MinorDeferred);
    assert!(deferred.change_ratio >= 0.005);
    assert!(deferred.change_ratio < 0.08);

    let kept = engine.evaluate_frame(change, 20_000, false);
    assert!(kept.keep);
    assert_eq!(kept.reason, FfiKeepReason::Changed);
}

#[test]
fn small_edits_accumulate_against_the_last_kept_frame() {
    let (_temp, _data_dir, engine) = open_engine();
    assert_eq!(
        engine.evaluate_frame(thumbnail(0), 0, false).reason,
        FfiKeepReason::FirstFrame
    );
    let deferred = engine.evaluate_frame(minor_change(0), 2_000, false);
    assert!(!deferred.keep);
    assert_eq!(deferred.reason, FfiKeepReason::MinorDeferred);

    // Twelve tiles against the kept frame cross the major ratio, even though
    // the deferred frame was never stored as the new comparison base.
    let accumulated = engine.evaluate_frame(changed_tiles(0, 12), 4_000, false);
    assert!(accumulated.keep);
    assert_eq!(accumulated.reason, FfiKeepReason::MajorChanged);
    assert!(accumulated.change_ratio >= 0.08);
}

#[test]
fn keeps_a_major_change_at_once() {
    let (_temp, _data_dir, engine) = open_engine();
    assert!(engine.evaluate_frame(thumbnail(0), 0, false).keep);
    let decision = engine.evaluate_frame(thumbnail(200), 2_000, false);
    assert!(decision.keep);
    assert_eq!(decision.reason, FfiKeepReason::MajorChanged);
}

#[test]
fn throttles_continuous_motion_to_the_motion_gap() {
    let (_temp, _data_dir, engine) = open_engine();
    assert!(engine.evaluate_frame(thumbnail(0), 0, false).keep);

    // Three quick major keeps at 2 s intervals start the motion run.
    for (step, fill) in [200, 100, 20].into_iter().enumerate() {
        let now_ms = 2_000 * (i64::try_from(step).unwrap() + 1);
        let decision = engine.evaluate_frame(thumbnail(fill), now_ms, false);
        assert!(decision.keep, "{fill} at {now_ms}");
        assert_eq!(decision.reason, FfiKeepReason::MajorChanged);
    }

    // Until ten seconds after the 6 s keep, a major frame is throttled.
    for (step, fill) in [100, 110, 120, 130].into_iter().enumerate() {
        let now_ms = 6_000 + 2_000 * (i64::try_from(step).unwrap() + 1);
        let decision = engine.evaluate_frame(thumbnail(fill), now_ms, false);
        assert!(!decision.keep, "at {now_ms}");
        assert_eq!(decision.reason, FfiKeepReason::MotionThrottled);
    }

    let kept = engine.evaluate_frame(thumbnail(240), 16_000, false);
    assert!(kept.keep);
    assert_eq!(kept.reason, FfiKeepReason::MajorChanged);
}

#[test]
fn throttles_a_video_through_quiet_frames() {
    let (_temp, _data_dir, engine) = open_engine();
    let mut kept_times = Vec::new();
    let mut throttled = 0;
    for second in 0..=60 {
        let now_ms = i64::try_from(second).unwrap() * 1_000;
        let decision = engine.evaluate_frame(thumbnail(video_fill(second)), now_ms, false);
        if second == 3 {
            assert_eq!(decision.reason, FfiKeepReason::Unchanged);
        }
        if decision.reason == FfiKeepReason::MotionThrottled {
            throttled += 1;
        }
        if decision.keep {
            kept_times.push(now_ms);
        }
    }
    assert!(throttled > 0);
    assert!(
        kept_times.len() <= MOTION_RUN_KEEPS + 6,
        "kept {} frames at {kept_times:?}",
        kept_times.len()
    );
    for pair in kept_times[MOTION_RUN_KEEPS..].windows(2) {
        assert!(
            pair[1] - pair[0] >= MOTION_GAP_MS,
            "keeps {} ms apart at {kept_times:?}",
            pair[1] - pair[0]
        );
    }
}

#[test]
fn motion_ends_after_a_pause_longer_than_the_motion_gap() {
    let (_temp, _data_dir, engine) = open_engine();
    assert_eq!(
        engine.evaluate_frame(thumbnail(0), 0, false).reason,
        FfiKeepReason::FirstFrame
    );
    // Three quick major keeps start the motion run.
    for (step, fill) in [200, 0, 200].into_iter().enumerate() {
        let now_ms = 2_000 * (i64::try_from(step).unwrap() + 1);
        let decision = engine.evaluate_frame(thumbnail(fill), now_ms, false);
        assert!(decision.keep, "{fill} at {now_ms}");
        assert_eq!(decision.reason, FfiKeepReason::MajorChanged);
    }
    // Fifteen seconds with no major change, then a major change is kept at once.
    for second in 7..=21 {
        let now_ms = second * 1_000;
        let decision = engine.evaluate_frame(thumbnail(200), now_ms, false);
        assert!(!decision.keep, "at {now_ms}");
        assert_eq!(decision.reason, FfiKeepReason::Unchanged);
    }
    let decision = engine.evaluate_frame(thumbnail(0), 22_000, false);
    assert!(decision.keep);
    assert_eq!(decision.reason, FfiKeepReason::MajorChanged);
}

#[test]
fn a_focus_change_passes_during_motion() {
    let (_temp, _data_dir, engine) = open_engine();
    assert!(engine.evaluate_frame(thumbnail(0), 0, false).keep);
    for (step, fill) in [200, 100, 20].into_iter().enumerate() {
        let now_ms = 2_000 * (i64::try_from(step).unwrap() + 1);
        assert!(engine.evaluate_frame(thumbnail(fill), now_ms, false).keep);
    }
    // An unchanged thumbnail still passes when the focused app changed.
    let decision = engine.evaluate_frame(thumbnail(20), 8_000, true);
    assert!(decision.keep);
    assert_eq!(decision.reason, FfiKeepReason::FocusChanged);
}

#[test]
fn the_max_gap_passes_during_motion() {
    let (_temp, _data_dir, engine) = open_engine();
    assert!(engine.evaluate_frame(thumbnail(0), 0, false).keep);
    for (step, fill) in [200, 100, 20].into_iter().enumerate() {
        let now_ms = 2_000 * (i64::try_from(step).unwrap() + 1);
        assert!(engine.evaluate_frame(thumbnail(fill), now_ms, false).keep);
    }
    let decision = engine.evaluate_frame(thumbnail(30), 306_000, false);
    assert!(decision.keep);
    assert_eq!(decision.reason, FfiKeepReason::MaxGap);
}

#[test]
fn a_kept_motion_frame_ends_the_throttle_until_the_next_gap() {
    let (_temp, _data_dir, engine) = open_engine();
    assert!(engine.evaluate_frame(thumbnail(0), 0, false).keep);
    for (step, fill) in [200, 100, 20].into_iter().enumerate() {
        let now_ms = 2_000 * (i64::try_from(step).unwrap() + 1);
        assert!(engine.evaluate_frame(thumbnail(fill), now_ms, false).keep);
    }
    assert!(engine.evaluate_frame(thumbnail(240), 16_000, false).keep);
    // The next frame arrives two seconds later, still inside the motion gap.
    assert_eq!(
        engine.evaluate_frame(thumbnail(60), 18_000, false).reason,
        FfiKeepReason::MotionThrottled
    );
}
