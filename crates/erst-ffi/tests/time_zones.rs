//! Local days in a named zone, including the 25 hour day that New York has on 2026-11-01.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::{frame, open_engine};
use erst_core::{MS_PER_HOUR, MS_PER_MINUTE};
use erst_ffi::ErstError;

type TestResult = Result<(), Box<dyn std::error::Error>>;

const NEW_YORK: &str = "America/New_York";
/// 2026-11-01T04:00Z: local midnight in New York, still on EDT (UTC-4).
const FALL_BACK_MIDNIGHT_MS: i64 = 1_793_505_600_000;

#[test]
fn since_starts_at_local_midnight_on_a_fall_back_day() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment = engine.begin_segment(
        "segments/dst.mp4".into(),
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    // 03:30Z is 23:30 on Oct 31 in New York. 04:30Z is 00:30 on Nov 1.
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR / 2,
        "dstmarker early",
    ))?;
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS + MS_PER_HOUR / 2,
        "dstmarker late",
    ))?;

    let hits = engine.search("dstmarker since:2026-11-01".into(), 10, NEW_YORK.into())?;

    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].matched_lines[0].text, "dstmarker late");
    Ok(())
}

#[test]
fn until_ends_at_the_end_of_the_local_day_on_a_fall_back_day() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment = engine.begin_segment(
        "segments/dst.mp4".into(),
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR / 2,
        "dstmarker early",
    ))?;
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS + MS_PER_HOUR / 2,
        "dstmarker late",
    ))?;

    let hits = engine.search("dstmarker until:2026-10-31".into(), 10, NEW_YORK.into())?;

    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].matched_lines[0].text, "dstmarker early");
    Ok(())
}

#[test]
fn today_summary_starts_at_local_midnight_on_a_fall_back_day() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let before = engine.begin_segment(
        "segments/before.mp4".into(),
        FALL_BACK_MIDNIGHT_MS - MS_PER_MINUTE * 30,
        1_920,
        1_080,
    )?;
    engine.finish_segment(before, FALL_BACK_MIDNIGHT_MS - MS_PER_MINUTE, 500)?;
    let today = engine.begin_segment(
        "segments/today.mp4".into(),
        FALL_BACK_MIDNIGHT_MS + MS_PER_MINUTE * 30,
        1_920,
        1_080,
    )?;
    engine.finish_segment(today, FALL_BACK_MIDNIGHT_MS + MS_PER_HOUR, 1_000)?;
    // 15:00Z on Nov 1 is 10:00 in New York.
    let now = FALL_BACK_MIDNIGHT_MS + 11 * MS_PER_HOUR;

    let summary = engine.today_summary(now, NEW_YORK.into(), 24)?;

    assert_eq!(
        summary.kept_bytes, 1_000,
        "the segment from 00:30 counts, the one from the day before does not"
    );
    Ok(())
}

#[test]
fn an_unknown_time_zone_is_invalid_input() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();

    let error = engine
        .search("anything".into(), 10, "Mars/Base".into())
        .unwrap_err();

    assert!(matches!(error, ErstError::InvalidInput { .. }), "{error}");
    Ok(())
}

#[test]
fn hourly_heat_puts_each_frame_in_its_local_day_and_hour() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment = engine.begin_segment(
        "segments/hours.mp4".into(),
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR,
        1_920,
        1_080,
    )?;
    // 03:30Z is 23:30 on Oct 31 in New York. 15:30Z is 10:30 on Nov 1, after the fall back.
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS - MS_PER_HOUR / 2,
        "late",
    ))?;
    engine.record_frame(frame(
        segment,
        FALL_BACK_MIDNIGHT_MS + 11 * MS_PER_HOUR + MS_PER_HOUR / 2,
        "morning",
    ))?;

    let days = engine.hourly_heat(
        FALL_BACK_MIDNIGHT_MS - 24 * MS_PER_HOUR,
        FALL_BACK_MIDNIGHT_MS + 25 * MS_PER_HOUR,
        NEW_YORK.into(),
    )?;

    assert_eq!(days.len(), 2);
    assert_eq!(days[1].start_ms, FALL_BACK_MIDNIGHT_MS);
    assert_eq!(days[1].end_ms - days[1].start_ms, 25 * MS_PER_HOUR);
    let lit = |hours: &[u8]| {
        hours
            .iter()
            .enumerate()
            .filter(|(_, level)| **level > 0)
            .map(|(hour, _)| hour)
            .collect::<Vec<_>>()
    };
    assert_eq!(lit(&days[0].hours), vec![23]);
    assert_eq!(lit(&days[1].hours), vec![10]);
    Ok(())
}

#[test]
fn hourly_heat_rejects_an_unknown_zone() {
    let (_temp, _data_dir, engine) = open_engine();
    let error = engine
        .hourly_heat(0, MS_PER_HOUR, "Mars/Olympus".into())
        .unwrap_err();
    assert!(matches!(error, ErstError::InvalidInput { .. }));
}
