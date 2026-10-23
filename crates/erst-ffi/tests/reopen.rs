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

#[test]
fn frames_a_crashed_file_never_got_are_dropped_on_request() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let started = current_time_ms() - MS_PER_HOUR;
    let crashed = engine.begin_segment("segments/cut.mp4".into(), started, 1_920, 1_080)?;
    for (pts, text) in [
        (0, "written zebra"),
        (2_000, "written yak"),
        (4_000, "unwritten quokka"),
    ] {
        let mut kept = frame(crashed, started + pts, text);
        kept.pts_ms = pts;
        engine.record_frame(kept)?;
    }
    write_video(&data_dir, "segments/cut.mp4");
    // The earlier run is killed with the newest frame still inside the video writer.
    drop(engine);

    let engine = Engine::open(data_dir.to_string_lossy().into_owned())?;
    let recovered = engine.recovered_segments();
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].segment_id, crashed);
    let path = recovered[0].path.clone();
    assert!(path.ends_with("segments/cut.mp4"), "{path}");
    assert_eq!(
        engine.finished_segment_videos()?.len(),
        1,
        "a finished segment with a video is listed for the one-time check"
    );

    // The file's video ends at 4000 ms, so the frame at 4000 never reached it.
    assert_eq!(engine.drop_unwritten_frames(crashed, 4_000)?, 1);
    let found = |query: &str| engine.search(query.into(), 10, "UTC".into());
    assert!(
        found("quokka")?.is_empty(),
        "the unwritten frame and its text are gone"
    );
    assert_eq!(found("zebra")?.len(), 1, "written frames stay");
    assert_eq!(found("yak")?.len(), 1, "written frames stay");

    // The segment this run is writing is refused.
    let live = engine.begin_segment("segments/live.mp4".into(), started + 10_000, 1_920, 1_080)?;
    assert!(engine.drop_unwritten_frames(live, 0).is_err());
    assert_eq!(
        engine.finished_segment_videos()?.len(),
        1,
        "the open segment is not listed"
    );
    drop(engine);

    let engine = Engine::open(data_dir.to_string_lossy().into_owned())?;
    assert_eq!(
        engine.recovered_segments().len(),
        1,
        "the live segment is recovered next time"
    );
    Ok(())
}
