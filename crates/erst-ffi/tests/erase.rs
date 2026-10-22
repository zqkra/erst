//! Erasing a range: database rows and segment videos.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::fs;

use common::{current_time_ms, frame, open_engine, write_video};
use erst_core::{MS_PER_HOUR, MS_PER_MINUTE};
use erst_ffi::{ErstError, FfiKeepReason, FfiThumbnail};

type TestResult = Result<(), Box<dyn std::error::Error>>;

fn thumbnail() -> FfiThumbnail {
    FfiThumbnail {
        width: 20,
        height: 10,
        luma: vec![0; 200],
    }
}

#[test]
fn erase_removes_frames_and_segment_videos() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let now = current_time_ms();

    let first_path = "segments/2026/10/05/first.mp4";
    let second_path = "segments/2026/10/05/second.mp4";
    let first_file = write_video(&data_dir, first_path);
    let second_file = write_video(&data_dir, second_path);
    let first_started = now - 10 * MS_PER_HOUR;
    let second_started = now - 5 * MS_PER_HOUR;
    let first_segment = engine.begin_segment(first_path.to_owned(), first_started, 1_920, 1_080)?;
    let second_segment =
        engine.begin_segment(second_path.to_owned(), second_started, 1_920, 1_080)?;
    let first_frame = engine.record_frame(frame(first_segment, first_started, "erase me"))?;
    engine.record_frame(frame(
        first_segment,
        first_started + MS_PER_MINUTE,
        "erase me too",
    ))?;
    engine.record_frame(frame(second_segment, second_started, "keep me"))?;
    engine.record_frame(frame(
        second_segment,
        second_started + MS_PER_MINUTE,
        "keep me too",
    ))?;
    engine.finish_segment(first_segment, first_started + 2 * MS_PER_MINUTE, 1_000_000)?;
    engine.finish_segment(
        second_segment,
        second_started + 2 * MS_PER_MINUTE,
        1_000_000,
    )?;

    // Two identical frames: the first is kept, the second is not.
    assert!(
        engine
            .evaluate_frame(thumbnail(), first_started, false)
            .keep
    );
    assert!(
        !engine
            .evaluate_frame(thumbnail(), first_started + MS_PER_MINUTE, false)
            .keep
    );

    let erased = engine.erase(now - 11 * MS_PER_HOUR, now - 8 * MS_PER_HOUR)?;
    assert_eq!(erased.frames_removed, 2);
    assert_eq!(erased.erased_from_ms, now - 11 * MS_PER_HOUR);
    assert_eq!(erased.erased_to_ms, now - 8 * MS_PER_HOUR);
    assert!(!first_file.exists());
    assert!(second_file.exists());
    assert!(matches!(
        engine.moment(first_frame, "UTC".to_owned()),
        Err(ErstError::NotFound { .. })
    ));
    assert!(
        engine
            .search("erase".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert_eq!(
        engine
            .search("keep".to_owned(), 10, "UTC".to_owned())?
            .len(),
        1
    );

    // Erasing forgets the last kept thumbnail, so the next frame is kept even
    // when it looks like the erased one.
    let kept = engine.evaluate_frame(thumbnail(), now, false);
    assert!(kept.keep);
    assert_eq!(kept.reason, FfiKeepReason::FirstFrame);

    // A video already missing from disk is not an error.
    fs::remove_file(&second_file)?;
    let erased = engine.erase(now - 6 * MS_PER_HOUR, now - 3 * MS_PER_HOUR)?;
    assert_eq!(erased.frames_removed, 2);
    assert!(
        engine
            .search("keep".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert_eq!(engine.storage()?.frame_count, 0);
    assert_eq!(engine.storage()?.segment_count, 0);

    // A range whose end precedes its start is rejected like every other range.
    assert!(matches!(
        engine.erase(now, now - MS_PER_MINUTE),
        Err(ErstError::InvalidInput { .. })
    ));
    Ok(())
}
