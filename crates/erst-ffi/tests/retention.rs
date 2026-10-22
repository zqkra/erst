//! Retention: what happens after the lighter copy period and under budget.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::{current_time_ms, frame, open_engine, write_video};
use erst_core::{MS_PER_DAY, MS_PER_HOUR};
use erst_ffi::{ErstError, FfiAfterLighterCopy, FfiRetentionKind, FfiSettings};

type TestResult = Result<(), Box<dyn std::error::Error>>;

#[test]
fn deletes_everything_after_the_lighter_copy() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();

    let path = "segments/2026/01/01/old.mp4";
    let old_file = write_video(&data_dir, path);
    let old_started = now - 40 * MS_PER_DAY;
    let old_segment = engine.begin_segment(path.to_owned(), old_started, 1_920, 1_080)?;
    let frame_id = engine.record_frame(frame(old_segment, old_started, "old note"))?;
    engine.finish_segment(old_segment, old_started + MS_PER_HOUR, 1_000_000)?;

    // The open segment is never planned, and neither is the newest closed one.
    engine.begin_segment("segments/open.mp4".to_owned(), now, 1_920, 1_080)?;
    let recent = engine.begin_segment(
        "segments/recent.mp4".to_owned(),
        now - 2 * MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    engine.finish_segment(recent, now - MS_PER_HOUR, 500_000)?;

    engine.update_settings(FfiSettings {
        full_quality_days: 1,
        lighter_copy_months: Some(1),
        after_lighter_copy: FfiAfterLighterCopy::DeleteEverything,
        storage_limit_gigabytes: None,
        ..FfiSettings::default()
    })?;

    let plan = engine.retention_plan(now)?;
    assert_eq!(plan.len(), 1);
    assert_eq!(plan[0].segment_id, old_segment);
    assert_eq!(plan[0].kind, FfiRetentionKind::DeleteSegment);
    assert_eq!(
        plan[0].segment_path.as_deref(),
        Some(old_file.to_string_lossy().as_ref())
    );

    engine.apply_retention(plan[0].clone(), None)?;
    assert!(!old_file.exists());
    assert_eq!(engine.storage()?.segment_count, 2);
    assert_eq!(engine.storage()?.frame_count, 0);
    assert!(matches!(
        engine.moment(frame_id, "UTC".to_owned()),
        Err(ErstError::NotFound { .. })
    ));
    assert!(
        engine
            .search("note".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert!(engine.retention_plan(now)?.is_empty());
    Ok(())
}

#[test]
fn the_storage_budget_keeps_the_text() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();

    let path = "segments/2026/10/05/budget.mp4";
    let file = write_video(&data_dir, path);
    let started = now - MS_PER_HOUR;
    let segment = engine.begin_segment(path.to_owned(), started, 1_920, 1_080)?;
    let frame_id = engine.record_frame(frame(segment, started, "budget note"))?;
    engine.finish_segment(segment, started + MS_PER_HOUR, 1_000_000)?;
    engine.begin_segment("segments/open.mp4".to_owned(), now, 1_920, 1_080)?;
    let recent = engine.begin_segment(
        "segments/recent.mp4".to_owned(),
        now - MS_PER_HOUR / 2,
        1_920,
        1_080,
    )?;
    engine.finish_segment(recent, now - MS_PER_HOUR / 4, 500_000)?;

    // Deleting everything is the choice after the lighter copy period. The
    // budget is a separate reason to delete, and it keeps the text.
    engine.update_settings(FfiSettings {
        full_quality_days: 30,
        lighter_copy_months: Some(12),
        after_lighter_copy: FfiAfterLighterCopy::DeleteEverything,
        storage_limit_gigabytes: Some(0),
        ..FfiSettings::default()
    })?;

    let plan = engine.retention_plan(now)?;
    assert_eq!(plan.len(), 1);
    assert_eq!(plan[0].segment_id, segment);
    assert_eq!(plan[0].kind, FfiRetentionKind::DeleteVideo);

    engine.apply_retention(plan[0].clone(), None)?;
    assert!(!file.exists());
    assert_eq!(
        engine.moment(frame_id, "UTC".to_owned())?.segment_path,
        None
    );
    assert_eq!(
        engine
            .search("budget".to_owned(), 10, "UTC".to_owned())?
            .len(),
        1
    );
    Ok(())
}
