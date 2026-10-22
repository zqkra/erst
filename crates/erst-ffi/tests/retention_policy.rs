//! What retention plans once a segment's lighter copy period has ended, under each choice.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::path::Path;

use common::{current_time_ms, frame, open_engine, write_video};
use erst_core::{MS_PER_DAY, MS_PER_HOUR};
use erst_ffi::{Engine, FfiAfterLighterCopy, FfiRetentionAction, FfiRetentionKind, FfiSettings};

type TestResult = Result<(), Box<dyn std::error::Error>>;

/// Ids of a segment that already lost its video and a segment that kept it.
struct Aged {
    trimmed: i64,
    control: i64,
}

/// Two segments 90 days old and one recent segment, with text in each old one.
fn record_aged_segments(
    engine: &Engine,
    data_dir: &Path,
    now: i64,
) -> Result<Aged, Box<dyn std::error::Error>> {
    let aged = now - 90 * MS_PER_DAY;
    write_video(data_dir, "segments/trimmed.mp4");
    let trimmed = engine.begin_segment("segments/trimmed.mp4".into(), aged, 1_920, 1_080)?;
    engine.record_frame(frame(trimmed, aged, "trimmed text"))?;
    engine.finish_segment(trimmed, aged + MS_PER_HOUR, 5)?;
    engine.apply_retention(
        FfiRetentionAction {
            segment_id: trimmed,
            kind: FfiRetentionKind::DeleteVideo,
            segment_path: None,
        },
        None,
    )?;

    write_video(data_dir, "segments/control.mp4");
    let control = engine.begin_segment(
        "segments/control.mp4".into(),
        aged + 5 * MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    engine.record_frame(frame(control, aged + 5 * MS_PER_HOUR, "control text"))?;
    engine.finish_segment(control, aged + 6 * MS_PER_HOUR, 5)?;

    let newest = engine.begin_segment(
        "segments/newest.mp4".into(),
        now - MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    engine.finish_segment(newest, now - MS_PER_HOUR + MS_PER_HOUR / 2, 5)?;
    Ok(Aged { trimmed, control })
}

fn kind_of(plan: &[FfiRetentionAction], segment_id: i64) -> Option<FfiRetentionKind> {
    plan.iter()
        .find(|action| action.segment_id == segment_id)
        .map(|action| action.kind)
}

fn settings_after_one_month(choice: FfiAfterLighterCopy) -> FfiSettings {
    FfiSettings {
        after_lighter_copy: choice,
        lighter_copy_months: Some(1),
        ..FfiSettings::default()
    }
}

#[test]
fn delete_everything_plans_text_only_and_full_segments_for_deletion() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();
    let aged = record_aged_segments(&engine, &data_dir, now)?;
    engine.update_settings(settings_after_one_month(
        FfiAfterLighterCopy::DeleteEverything,
    ))?;

    let plan = engine.retention_plan(now)?;

    assert_eq!(
        kind_of(&plan, aged.trimmed),
        Some(FfiRetentionKind::DeleteSegment)
    );
    assert_eq!(
        kind_of(&plan, aged.control),
        Some(FfiRetentionKind::DeleteSegment)
    );
    engine.apply_retention(
        FfiRetentionAction {
            segment_id: aged.trimmed,
            kind: FfiRetentionKind::DeleteSegment,
            segment_path: None,
        },
        None,
    )?;
    assert!(
        engine
            .search("\"trimmed\"".into(), 10, "UTC".into())?
            .is_empty()
    );
    Ok(())
}

#[test]
fn keep_text_plans_no_action_for_text_only_segments() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();
    let aged = record_aged_segments(&engine, &data_dir, now)?;
    engine.update_settings(settings_after_one_month(FfiAfterLighterCopy::KeepText))?;

    let plan = engine.retention_plan(now)?;

    assert_eq!(kind_of(&plan, aged.trimmed), None);
    assert_eq!(
        kind_of(&plan, aged.control),
        Some(FfiRetentionKind::DeleteVideo)
    );
    Ok(())
}
