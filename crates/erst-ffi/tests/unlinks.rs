//! Videos whose rows are gone but whose files could not be deleted.
//!
//! A locked directory makes every delete in it fail. The database change still
//! commits, and the file waits in the pending list until a later pass can
//! delete it.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use common::{current_time_ms, frame, open_engine, write_video};
use erst_core::{MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE};
use erst_ffi::{Engine, FfiRetentionAction, FfiRetentionKind};

type TestResult = Result<(), Box<dyn std::error::Error>>;

/// Makes a directory read-only so nothing inside it can be deleted, or writable again.
fn set_dir_mode(dir: &Path, mode: u32) {
    fs::set_permissions(dir, fs::Permissions::from_mode(mode)).unwrap();
}

#[test]
fn erase_succeeds_and_deletes_the_videos_it_can_reach() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let base = current_time_ms() - 2 * MS_PER_HOUR;
    write_video(&data_dir, "segments/locked/a.mp4");
    write_video(&data_dir, "segments/free/b.mp4");
    let locked = engine.begin_segment("segments/locked/a.mp4".into(), base, 1_920, 1_080)?;
    let free = engine.begin_segment(
        "segments/free/b.mp4".into(),
        base + MS_PER_MINUTE,
        1_920,
        1_080,
    )?;
    engine.record_frame(frame(locked, base, "locked text"))?;
    engine.record_frame(frame(free, base + MS_PER_MINUTE, "free text"))?;
    engine.finish_segment(locked, base + 2 * MS_PER_MINUTE, 5)?;
    engine.finish_segment(free, base + 2 * MS_PER_MINUTE, 5)?;
    set_dir_mode(&data_dir.join("segments/locked"), 0o555);

    let erased = engine.erase(base - 1, base + 10 * MS_PER_MINUTE)?;

    assert_eq!(erased.frames_removed, 2);
    assert!(erased.purge_complete);
    assert_eq!(engine.storage()?.frame_count, 0);
    assert!(!data_dir.join("segments/free/b.mp4").exists());
    assert!(data_dir.join("segments/locked/a.mp4").exists());
    assert_eq!(engine.pending_file_count()?, 1);
    set_dir_mode(&data_dir.join("segments/locked"), 0o755);
    engine.retention_plan(base + 3 * MS_PER_HOUR)?;
    assert_eq!(engine.pending_file_count()?, 0);
    Ok(())
}

#[test]
fn a_video_left_pending_is_deleted_by_the_next_retention_plan() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let base = current_time_ms() - 2 * MS_PER_HOUR;
    write_video(&data_dir, "segments/locked/a.mp4");
    let locked = engine.begin_segment("segments/locked/a.mp4".into(), base, 1_920, 1_080)?;
    engine.finish_segment(locked, base + MS_PER_MINUTE, 5)?;
    set_dir_mode(&data_dir.join("segments/locked"), 0o555);
    engine.erase(base - 1, base + 10 * MS_PER_MINUTE)?;
    assert!(data_dir.join("segments/locked/a.mp4").exists());

    assert_eq!(engine.pending_file_count()?, 1);
    set_dir_mode(&data_dir.join("segments/locked"), 0o755);
    engine.retention_plan(base + 3 * MS_PER_HOUR)?;

    assert!(!data_dir.join("segments/locked/a.mp4").exists());
    assert_eq!(engine.pending_file_count()?, 0);
    Ok(())
}

#[test]
fn reopening_the_engine_deletes_the_videos_left_pending() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let base = current_time_ms() - 2 * MS_PER_HOUR;
    write_video(&data_dir, "segments/locked/a.mp4");
    let locked = engine.begin_segment("segments/locked/a.mp4".into(), base, 1_920, 1_080)?;
    engine.finish_segment(locked, base + MS_PER_MINUTE, 5)?;
    set_dir_mode(&data_dir.join("segments/locked"), 0o555);
    engine.erase(base - 1, base + 10 * MS_PER_MINUTE)?;
    set_dir_mode(&data_dir.join("segments/locked"), 0o755);
    drop(engine);

    let _reopened = Engine::open(data_dir.to_string_lossy().into_owned())?;

    assert!(!data_dir.join("segments/locked/a.mp4").exists());
    Ok(())
}

#[test]
fn apply_retention_succeeds_and_leaves_an_undeletable_video_pending() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();
    let old_started = now - 30 * MS_PER_DAY;
    write_video(&data_dir, "segments/old/old.mp4");
    let old = engine.begin_segment("segments/old/old.mp4".into(), old_started, 1_920, 1_080)?;
    engine.record_frame(frame(old, old_started, "old text"))?;
    engine.finish_segment(old, old_started + MS_PER_MINUTE, 5)?;
    let newest = engine.begin_segment(
        "segments/new/new.mp4".into(),
        now - MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    engine.finish_segment(newest, now - MS_PER_HOUR + MS_PER_MINUTE, 5)?;
    set_dir_mode(&data_dir.join("segments/old"), 0o555);
    let action = FfiRetentionAction {
        segment_id: old,
        kind: FfiRetentionKind::DeleteVideo,
        segment_path: None,
    };

    engine.apply_retention(action, None)?;

    assert!(data_dir.join("segments/old/old.mp4").exists());
    set_dir_mode(&data_dir.join("segments/old"), 0o755);
    engine.retention_plan(now)?;
    assert!(!data_dir.join("segments/old/old.mp4").exists());
    assert_eq!(
        engine.search("\"old\"".into(), 10, "UTC".into())?.len(),
        1,
        "the text is kept"
    );
    Ok(())
}
