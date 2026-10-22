#![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

use super::{FrameContext, KeepPolicy, KeepReason, KeepState, Thumbnail};

fn thumbnail(width: u32, height: u32, fill: u8) -> Thumbnail {
    let len = usize::try_from(width).unwrap() * usize::try_from(height).unwrap();
    Thumbnail::new(width, height, vec![fill; len]).unwrap()
}

fn policy() -> KeepPolicy {
    KeepPolicy {
        ignore_top_fraction: 0.0,
        ..KeepPolicy::default()
    }
}

fn context(now_ms: i64, last_kept_ms: Option<i64>, focus_changed: bool) -> FrameContext {
    FrameContext {
        now_ms,
        last_kept_ms,
        focus_changed,
    }
}

/// A 160x90 thumbnail whose first `count` tiles in the top tile row are bright.
///
/// With the default grid that changes `count` of 144 compared tiles, so one
/// tile is a minor change (0.0069) and twelve tiles cross the major ratio.
fn thumbnail_with_changed_tiles(count: u32) -> Thumbnail {
    let mut next = thumbnail(160, 90, 0);
    for tile in 0..count {
        let left = usize::try_from(tile).unwrap() * 10;
        for row in 0..10 {
            for column in left..left + 10 {
                next.luma[row * 160 + column] = 200;
            }
        }
    }
    next
}

/// A minimal valid 160x90 major change against a black thumbnail.
fn major_change() -> Thumbnail {
    thumbnail(160, 90, 200)
}

#[test]
fn default_policy_matches_the_documented_values() {
    let policy = KeepPolicy::default();
    assert_eq!(policy.tile_size, 10);
    assert_eq!(policy.tile_threshold, 6);
    assert!((policy.keep_ratio - 0.005).abs() < f32::EPSILON);
    assert!((policy.major_ratio - 0.08).abs() < f32::EPSILON);
    assert!((policy.ignore_top_fraction - 0.04).abs() < f32::EPSILON);
    assert_eq!(policy.max_gap_ms, 300_000);
    assert_eq!(policy.minor_gap_ms, 20_000);
    assert_eq!(policy.motion_gap_ms, 10_000);
    assert_eq!(policy.motion_run_keeps, 3);
}

#[test]
fn thumbnail_new_rejects_zero_dimensions() {
    assert!(Thumbnail::new(0, 10, Vec::new()).is_err());
    assert!(Thumbnail::new(10, 0, Vec::new()).is_err());
    assert!(Thumbnail::new(0, 0, Vec::new()).is_err());
}

#[test]
fn thumbnail_new_rejects_buffer_length_mismatch() {
    let error = Thumbnail::new(4, 3, vec![0; 11]).unwrap_err();
    assert!(error.to_string().contains("expected 12"));
}

#[test]
fn thumbnail_new_accepts_a_matching_buffer() {
    let thumbnail = Thumbnail::new(4, 3, vec![7; 12]).unwrap();
    assert_eq!(thumbnail.width, 4);
    assert_eq!(thumbnail.height, 3);
    assert_eq!(thumbnail.luma.len(), 12);
}

#[test]
fn identical_frames_have_no_change() {
    let a = thumbnail(160, 90, 40);
    let b = thumbnail(160, 90, 40);
    assert!((policy().change_ratio(&a, &b) - 0.0).abs() < f32::EPSILON);
}

#[test]
fn dimension_mismatch_counts_as_complete_change() {
    let a = thumbnail(160, 90, 0);
    let b = thumbnail(80, 90, 0);
    assert!((policy().change_ratio(&a, &b) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn zero_tile_size_counts_as_complete_change() {
    let a = thumbnail(20, 20, 0);
    let b = thumbnail(20, 20, 1);
    let policy = KeepPolicy {
        tile_size: 0,
        ..KeepPolicy::default()
    };
    assert!((policy.change_ratio(&a, &b) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn inconsistent_buffer_counts_as_complete_change() {
    let a = Thumbnail {
        width: 10,
        height: 10,
        luma: Vec::new(),
    };
    let b = thumbnail(10, 10, 0);
    assert!((policy().change_ratio(&a, &b) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn skips_the_clock_band() {
    let a = thumbnail(160, 90, 0);
    let mut b = a.clone();
    // 90 rows at 4 percent ignore three rows.
    for row in 0..2 {
        for column in 0..160 {
            b.luma[row * 160 + column] = 255;
        }
    }
    assert!((KeepPolicy::default().change_ratio(&a, &b) - 0.0).abs() < f32::EPSILON);
}

#[test]
fn counts_the_changed_tile_row_below_the_clock_band() {
    let a = thumbnail(160, 90, 0);
    let mut b = a.clone();
    // Rows 5 to 8 sit in the first compared tile row. All 16 tile columns
    // change, out of 16 columns and 9 compared tile rows.
    for row in 5..9 {
        for column in 0..160 {
            b.luma[row * 160 + column] = 255;
        }
    }
    let ratio = KeepPolicy::default().change_ratio(&a, &b);
    assert!((ratio - 16.0 / 144.0).abs() < f32::EPSILON, "ratio {ratio}");
}

#[test]
fn compares_rows_below_the_clock_band() {
    let a = thumbnail(160, 90, 0);
    let mut b = a.clone();
    for column in 0..160 {
        b.luma[10 * 160 + column] = 255;
    }
    let ratio = KeepPolicy::default().change_ratio(&a, &b);
    assert!(ratio > 0.0);
}

#[test]
fn partial_tiles_use_their_real_pixel_count() {
    let a = thumbnail(15, 13, 0);
    let mut b = a.clone();
    b.luma[10 * 15 + 10] = 100;
    let ratio = policy().change_ratio(&a, &b);
    assert!((ratio - 0.25).abs() < f32::EPSILON);
}

#[test]
fn full_tile_threshold_is_strict() {
    let a = thumbnail(2, 2, 10);
    let at_threshold = thumbnail(2, 2, 16);
    let above_threshold = thumbnail(2, 2, 17);
    let policy = KeepPolicy {
        tile_size: 2,
        ..KeepPolicy::default()
    };
    assert!((policy.change_ratio(&a, &at_threshold) - 0.0).abs() < f32::EPSILON);
    assert!((policy.change_ratio(&a, &above_threshold) - 1.0).abs() < f32::EPSILON);
}

#[test]
fn change_ratio_is_changed_over_compared_tiles() {
    let a = thumbnail(30, 30, 0);
    let mut b = a.clone();
    for row in 0..10 {
        for column in 0..10 {
            b.luma[row * 30 + column] = 100;
        }
    }
    assert!((policy().change_ratio(&a, &b) - (1.0 / 9.0)).abs() < f32::EPSILON);
}

#[test]
fn ignoring_the_whole_image_compares_no_tiles() {
    let a = thumbnail(10, 10, 0);
    let b = thumbnail(10, 10, 255);
    let policy = KeepPolicy {
        ignore_top_fraction: 1.0,
        ..KeepPolicy::default()
    };
    assert!((policy.change_ratio(&a, &b) - 0.0).abs() < f32::EPSILON);
}

#[test]
fn decide_keeps_the_first_frame() {
    let next = thumbnail(20, 20, 0);
    let decision = policy().decide(
        None,
        &next,
        &context(10_000, None, false),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::FirstFrame);
    assert!((decision.change_ratio - 1.0).abs() < f32::EPSILON);
    assert_eq!(decision.next_state, KeepState::default());
}

#[test]
fn decide_treats_an_unknown_last_kept_time_as_the_first_frame() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(10_000, None, false),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::FirstFrame);
    assert!((decision.change_ratio - 0.0).abs() < f32::EPSILON);
}

#[test]
fn decide_skips_an_unchanged_frame() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(10_000, Some(9_000), false),
        KeepState::default(),
    );
    assert!(!decision.keep);
    assert_eq!(decision.reason, KeepReason::Unchanged);
}

#[test]
fn keeps_a_major_change_at_once() {
    let previous = major_change();
    let mut next = previous.clone();
    for index in 0..previous.luma.len() / 2 {
        next.luma[index] = 0;
    }
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(10_000, Some(9_000), false),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::MajorChanged);
    assert!(decision.change_ratio >= KeepPolicy::default().major_ratio);
}

#[test]
fn defers_a_minor_change_until_the_minor_gap() {
    let previous = thumbnail(160, 90, 0);
    let next = thumbnail_with_changed_tiles(1);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(10_000, Some(8_000), false),
        KeepState::default(),
    );
    assert!(!decision.keep);
    assert_eq!(decision.reason, KeepReason::MinorDeferred);
    assert!(decision.change_ratio >= KeepPolicy::default().keep_ratio);
    assert!(decision.change_ratio < KeepPolicy::default().major_ratio);
}

#[test]
fn keeps_a_minor_change_at_the_minor_gap() {
    let previous = thumbnail(160, 90, 0);
    let next = thumbnail_with_changed_tiles(1);
    let policy = policy();
    let at_boundary = policy.decide(
        Some(&previous),
        &next,
        &context(20_000, Some(0), false),
        KeepState::default(),
    );
    let before_boundary = policy.decide(
        Some(&previous),
        &next,
        &context(19_999, Some(0), false),
        KeepState::default(),
    );
    assert!(at_boundary.keep);
    assert_eq!(at_boundary.reason, KeepReason::Changed);
    assert!(!before_boundary.keep);
    assert_eq!(before_boundary.reason, KeepReason::MinorDeferred);
}

#[test]
fn a_change_at_the_keep_ratio_is_a_minor_change() {
    let previous = thumbnail(20, 20, 0);
    let mut next = previous.clone();
    for row in 0..10 {
        for column in 0..10 {
            next.luma[row * 20 + column] = 100;
        }
    }
    let policy = KeepPolicy {
        keep_ratio: 0.25,
        major_ratio: 0.5,
        ..policy()
    };
    let decision = policy.decide(
        Some(&previous),
        &next,
        &context(10_000, Some(9_000), false),
        KeepState::default(),
    );
    assert!((decision.change_ratio - 0.25).abs() < f32::EPSILON);
    assert!(!decision.keep);
    assert_eq!(decision.reason, KeepReason::MinorDeferred);
}

#[test]
fn focus_change_beats_the_max_gap() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(1_000_000, Some(0), true),
        KeepState::default(),
    );
    assert!(decision.keep);
    assert_eq!(decision.reason, KeepReason::FocusChanged);
    assert!((decision.change_ratio - 0.0).abs() < f32::EPSILON);
}

#[test]
fn max_gap_boundary_keeps_the_frame() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 0);
    let policy = KeepPolicy {
        max_gap_ms: 30_000,
        ..policy()
    };
    let at_boundary = policy.decide(
        Some(&previous),
        &next,
        &context(30_000, Some(0), false),
        KeepState::default(),
    );
    let below_boundary = policy.decide(
        Some(&previous),
        &next,
        &context(29_999, Some(0), false),
        KeepState::default(),
    );
    assert_eq!(at_boundary.reason, KeepReason::MaxGap);
    assert_eq!(below_boundary.reason, KeepReason::Unchanged);
}

#[test]
fn max_gap_reports_the_real_ratio() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 200);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(300_000, Some(0), false),
        KeepState::default(),
    );
    assert_eq!(decision.reason, KeepReason::MaxGap);
    assert!((decision.change_ratio - 1.0).abs() < f32::EPSILON);
}

#[test]
fn a_future_last_kept_time_does_not_expire_the_gap() {
    let previous = thumbnail(20, 20, 0);
    let next = thumbnail(20, 20, 0);
    let decision = policy().decide(
        Some(&previous),
        &next,
        &context(1_000, Some(2_000), false),
        KeepState::default(),
    );
    assert_eq!(decision.reason, KeepReason::Unchanged);
}

mod motion;

#[test]
fn ignored_rows_rounds_down_and_clamps() {
    assert_eq!(super::ignored_rows(90, 0.04), 3);
    assert_eq!(super::ignored_rows(100, 0.1), 10);
    assert_eq!(super::ignored_rows(10, -1.0), 0);
    assert_eq!(super::ignored_rows(10, 2.0), 10);
    assert_eq!(super::ignored_rows(10, f32::NAN), 0);
}

#[test]
fn top_row_inside_the_band_is_ignored_but_the_next_row_is_not() {
    let a = thumbnail(10, 100, 0);
    let mut b = a.clone();
    for column in 0..10 {
        b.luma[column] = 100;
    }
    let policy = KeepPolicy {
        ignore_top_fraction: 0.1,
        ..KeepPolicy::default()
    };
    assert!((policy.change_ratio(&a, &b) - 0.0).abs() < f32::EPSILON);
    for column in 0..10 {
        b.luma[10 * 10 + column] = 100;
    }
    assert!(policy.change_ratio(&a, &b) > 0.0);
}
