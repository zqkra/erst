#![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

use super::{
    AfterLighterCopy, REDUCED_SIZE_FACTOR, RetentionAction, RetentionKind, RetentionPolicy,
    SegmentInfo, Tier, plan,
};

const HOUR: i64 = 3_600_000;
const DAY: i64 = 24 * HOUR;

fn segment(id: i64, started_at: i64, bytes: u64, tier: Tier) -> SegmentInfo {
    SegmentInfo {
        id,
        started_at,
        bytes,
        tier,
    }
}

fn policy(full_quality_ms: i64, reduced_ms: Option<i64>) -> RetentionPolicy {
    RetentionPolicy {
        full_quality_ms,
        reduced_ms,
        budget_bytes: None,
        after_lighter_copy: AfterLighterCopy::KeepText,
    }
}

fn action(segment_id: i64, action: RetentionKind) -> RetentionAction {
    RetentionAction { segment_id, action }
}

#[test]
fn reduced_size_factor_is_thirty_five_percent() {
    assert!((REDUCED_SIZE_FACTOR - 0.35).abs() < f64::EPSILON);
    assert_eq!(super::reduced_bytes(1_000), 350);
}

#[test]
fn empty_input_plans_nothing() {
    assert!(plan(&policy(0, None), &[], 1_000_000).is_empty());
}

#[test]
fn never_acts_on_the_newest_segment() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(&policy(0, Some(0)), &segments, 100 * DAY);
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteVideo)]);
}

#[test]
fn never_acts_on_any_segment_tied_for_newest() {
    let segments = [
        segment(1, 10 * DAY, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    assert!(plan(&policy(0, Some(0)), &segments, 100 * DAY).is_empty());
}

#[test]
fn reduces_full_segments_after_the_full_quality_window() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(&policy(DAY, None), &segments, 2 * DAY);
    assert_eq!(planned, vec![action(1, RetentionKind::Reduce)]);
}

#[test]
fn full_quality_boundary_is_strict() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    assert!(plan(&policy(DAY, None), &segments, DAY).is_empty());
    let planned = plan(&policy(DAY, None), &segments, DAY + 1);
    assert_eq!(planned, vec![action(1, RetentionKind::Reduce)]);
}

#[test]
fn deletes_video_after_the_reduced_window_instead_of_reducing() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let policy = policy(DAY, Some(DAY));
    let at_boundary = plan(&policy, &segments, 2 * DAY);
    assert_eq!(at_boundary, vec![action(1, RetentionKind::Reduce)]);
    let past_boundary = plan(&policy, &segments, 2 * DAY + 1);
    assert_eq!(past_boundary, vec![action(1, RetentionKind::DeleteVideo)]);
}

#[test]
fn deletes_already_reduced_video_after_the_reduced_window() {
    let segments = [
        segment(1, 0, 1_000, Tier::Reduced),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let policy = policy(DAY, Some(DAY));
    assert!(plan(&policy, &segments, 2 * DAY).is_empty());
    assert_eq!(
        plan(&policy, &segments, 2 * DAY + 1),
        vec![action(1, RetentionKind::DeleteVideo)]
    );
}

#[test]
fn reduced_video_survives_without_a_reduced_window() {
    let segments = [
        segment(1, 0, 1_000, Tier::Reduced),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    assert!(plan(&policy(DAY, None), &segments, 1_000 * DAY).is_empty());
}

#[test]
fn text_only_segments_are_never_touched_by_aging() {
    let segments = [
        segment(1, 0, 1_000, Tier::TextOnly),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    assert!(plan(&policy(0, Some(0)), &segments, 1_000 * DAY).is_empty());
}

#[test]
fn actions_are_sorted_oldest_first() {
    let segments = [
        segment(3, 30 * DAY, 1_000, Tier::Full),
        segment(1, 10 * DAY, 1_000, Tier::Full),
        segment(2, 20 * DAY, 1_000, Tier::Full),
        segment(4, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(&policy(DAY, None), &segments, 200 * DAY);
    assert_eq!(
        planned,
        vec![
            action(1, RetentionKind::Reduce),
            action(2, RetentionKind::Reduce),
            action(3, RetentionKind::Reduce),
        ]
    );
}

#[test]
fn budget_is_not_enforced_when_already_under_it() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 100 * DAY,
        reduced_ms: None,
        budget_bytes: Some(2_000),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    assert!(plan(&policy, &segments, 100 * DAY).is_empty());
}

#[test]
fn budget_deletes_the_oldest_videos_first() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
        segment(3, 20 * DAY, 1_000, Tier::Full),
        segment(4, 30 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 100 * DAY,
        reduced_ms: None,
        budget_bytes: Some(3_500),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    let planned = plan(&policy, &segments, 0);
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteVideo)]);
}

#[test]
fn budget_skips_text_only_and_newest_segments() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 0, Tier::TextOnly),
        segment(3, 20 * DAY, 1_000, Tier::Full),
        segment(4, 30 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 100 * DAY,
        reduced_ms: None,
        budget_bytes: Some(0),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    let planned = plan(&policy, &segments, 0);
    assert_eq!(
        planned,
        vec![
            action(1, RetentionKind::DeleteVideo),
            action(3, RetentionKind::DeleteVideo),
        ]
    );
}

#[test]
fn budget_counts_a_planned_reduce_at_the_reduced_size() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: DAY,
        reduced_ms: None,
        budget_bytes: Some(1_400),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    assert_eq!(
        plan(&policy, &segments, 100 * DAY),
        vec![action(1, RetentionKind::Reduce)]
    );
}

#[test]
fn budget_counts_already_reduced_bytes_as_stored() {
    let segments = [
        segment(1, 0, 350, Tier::Reduced),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 100 * DAY,
        reduced_ms: None,
        budget_bytes: Some(1_200),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    assert_eq!(
        plan(&policy, &segments, 0),
        vec![action(1, RetentionKind::DeleteVideo)]
    );
}

#[test]
fn budget_delete_supersedes_a_planned_reduce() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: DAY,
        reduced_ms: None,
        budget_bytes: Some(500),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    let planned = plan(&policy, &segments, 100 * DAY);
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteVideo)]);
}

#[test]
fn budget_with_only_the_newest_segment_cannot_act() {
    let segments = [segment(1, 0, 10_000, Tier::Full)];
    let policy = RetentionPolicy {
        full_quality_ms: 0,
        reduced_ms: Some(0),
        budget_bytes: Some(0),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    assert!(plan(&policy, &segments, 100 * DAY).is_empty());
}

#[test]
fn text_only_segments_count_as_zero_bytes_in_the_budget() {
    let segments = [
        segment(1, 0, 10_000, Tier::TextOnly),
        segment(2, 10 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 100 * DAY,
        reduced_ms: None,
        budget_bytes: Some(1_000),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    assert!(plan(&policy, &segments, 0).is_empty());
}

#[test]
fn delete_actions_are_planned_once_per_segment() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 10 * DAY, 1_000, Tier::Full),
        segment(3, 20 * DAY, 1_000, Tier::Full),
    ];
    let policy = RetentionPolicy {
        full_quality_ms: 0,
        reduced_ms: Some(0),
        budget_bytes: Some(0),
        after_lighter_copy: AfterLighterCopy::KeepText,
    };
    let planned = plan(&policy, &segments, 100 * DAY);
    assert_eq!(
        planned,
        vec![
            action(1, RetentionKind::DeleteVideo),
            action(2, RetentionKind::DeleteVideo),
        ]
    );
}

fn delete_everything(
    full_quality_ms: i64,
    reduced_ms: Option<i64>,
    budget_bytes: Option<u64>,
) -> RetentionPolicy {
    RetentionPolicy {
        full_quality_ms,
        reduced_ms,
        budget_bytes,
        after_lighter_copy: AfterLighterCopy::DeleteEverything,
    }
}

#[test]
fn delete_everything_removes_an_old_full_segment_with_its_frames() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(
        &delete_everything(DAY, Some(DAY), None),
        &segments,
        100 * DAY,
    );
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteSegment)]);
}

#[test]
fn delete_everything_removes_an_old_text_only_segment() {
    let segments = [
        segment(1, 0, 1_000, Tier::TextOnly),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(
        &delete_everything(DAY, Some(DAY), None),
        &segments,
        100 * DAY,
    );
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteSegment)]);
}

#[test]
fn delete_everything_keeps_a_text_only_segment_inside_the_lighter_copy_period() {
    let segments = [
        segment(1, 99 * DAY, 1_000, Tier::TextOnly),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    assert!(
        plan(
            &delete_everything(DAY, Some(10 * DAY), None),
            &segments,
            100 * DAY
        )
        .is_empty()
    );
}

#[test]
fn delete_everything_still_reduces_before_the_lighter_copy_ends() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(
        &delete_everything(DAY, Some(200 * DAY), None),
        &segments,
        100 * DAY,
    );
    assert_eq!(planned, vec![action(1, RetentionKind::Reduce)]);
}

#[test]
fn delete_everything_without_a_lighter_copy_limit_never_deletes_by_age() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, 0, 1_000, Tier::TextOnly),
        segment(3, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(&delete_everything(DAY, None, None), &segments, 100 * DAY);
    assert_eq!(planned, vec![action(1, RetentionKind::Reduce)]);
}

#[test]
fn keep_text_never_removes_a_text_only_segment_after_the_lighter_copy() {
    let segments = [
        segment(1, 0, 1_000, Tier::TextOnly),
        segment(2, 100 * DAY, 1_000, Tier::Full),
    ];
    assert!(plan(&policy(DAY, Some(DAY)), &segments, 100 * DAY).is_empty());
}

#[test]
fn budget_deletes_keep_the_text_under_delete_everything() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, DAY, 1_000, Tier::Full),
        segment(3, 2 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(
        &delete_everything(100 * DAY, None, Some(2_000)),
        &segments,
        0,
    );
    assert_eq!(planned, vec![action(1, RetentionKind::DeleteVideo)]);
}

#[test]
fn budget_skips_a_segment_already_scheduled_for_deletion() {
    let segments = [
        segment(1, 0, 1_000, Tier::Full),
        segment(2, DAY, 1_000, Tier::Full),
        segment(3, 100 * DAY, 1_000, Tier::Full),
    ];
    let planned = plan(
        &delete_everything(DAY, Some(DAY), Some(1_000)),
        &segments,
        100 * DAY,
    );
    assert_eq!(
        planned,
        vec![
            action(1, RetentionKind::DeleteSegment),
            action(2, RetentionKind::DeleteSegment),
        ]
    );
}
