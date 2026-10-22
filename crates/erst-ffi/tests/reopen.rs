//! What an engine finds when it opens a data directory that an earlier run left.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::{SAFARI, current_time_ms, frame, open_engine, write_video};
use erst_core::{MS_PER_DAY, MS_PER_HOUR};
use erst_ffi::Engine;

type TestResult = Result<(), Box<dyn std::error::Error>>;

#[test]
fn a_span_left_open_by_an_earlier_run_ends_at_the_newest_frame() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let started = current_time_ms() - 3 * MS_PER_DAY;
    let segment = engine.begin_segment("segments/earlier.mp4".into(), started, 1_920, 1_080)?;
    engine.begin_span(
        SAFARI.into(),
        "Safari".into(),
        Some("Apple".into()),
        None,
        started,
    )?;
    engine.record_frame(frame(segment, started + 2 * MS_PER_HOUR, "earlier text"))?;
    // The earlier run stops here, so the span never gets an end.
    drop(engine);

    let engine = Engine::open(data_dir.to_string_lossy().into_owned())?;

    let report = engine.activity(
        started - MS_PER_DAY,
        started + 2 * MS_PER_DAY,
        "UTC".to_owned(),
    )?;
    assert_eq!(report.total_ms, 2 * MS_PER_HOUR, "not three days");
    Ok(())
}

#[test]
fn a_segment_left_open_by_a_crash_is_finished_with_its_newest_frame_and_size() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let started = current_time_ms() - MS_PER_HOUR;
    let finished = engine.begin_segment("segments/finished.mp4".into(), started, 1_920, 1_080)?;
    engine.record_frame(frame(finished, started + 1_000, "finished text"))?;
    engine.finish_segment(finished, started + 60_000, 4_096)?;
    let crashed = engine.begin_segment(
        "segments/crashed.mp4".into(),
        started + 60_000,
        1_920,
        1_080,
    )?;
    engine.record_frame(frame(crashed, started + 61_000, "first text"))?;
    engine.record_frame(frame(crashed, started + 90_000, "second text"))?;
    let video = write_video(&data_dir, "segments/crashed.mp4");
    let video_bytes = std::fs::metadata(&video)?.len();
    // The earlier run is killed here, so the segment never gets an end or a size.
    drop(engine);

    let engine = Engine::open(data_dir.to_string_lossy().into_owned())?;
    let storage = engine.storage()?;
    assert_eq!(
        storage.video_bytes,
        4_096 + video_bytes,
        "the crashed file is counted"
    );
    assert_eq!(storage.segment_count, 2);
    drop(engine);

    // Opening again finds nothing left to finish and changes nothing.
    let engine = Engine::open(data_dir.to_string_lossy().into_owned())?;
    assert_eq!(engine.storage()?.video_bytes, 4_096 + video_bytes);
    Ok(())
}
