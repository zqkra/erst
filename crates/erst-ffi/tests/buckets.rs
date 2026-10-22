//! Bucket widths, local day buckets, and the limit that keeps one request from
//! allocating without bound.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::{SAFARI, current_time_ms, open_engine};
use erst_core::{MS_PER_DAY, MS_PER_HOUR};
use erst_ffi::{ErstError, FfiBucketKind};

type TestResult = Result<(), Box<dyn std::error::Error>>;

const NEW_YORK: &str = "America/New_York";
/// 2026-11-01T04:00Z: local midnight in New York, still on EDT (UTC-4).
const FALL_BACK_WEEK_START_MS: i64 = 1_793_505_600_000;
/// 2026-11-08T05:00Z: local midnight on the next Sunday, now on EST (UTC-5).
const FALL_BACK_WEEK_END_MS: i64 = 1_794_114_000_000;

#[test]
fn an_all_time_activity_request_is_invalid_input() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    // From year 1 to now is far more days than the bucket limit allows.
    let error = engine
        .activity(-62_135_596_800_000, current_time_ms(), "UTC".to_owned())
        .unwrap_err();
    assert!(matches!(error, ErstError::InvalidInput { .. }), "{error}");
    Ok(())
}

#[test]
fn activity_uses_hour_buckets_up_to_three_days_and_day_buckets_after() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let now = current_time_ms();

    let short = engine.activity(now - 2 * MS_PER_HOUR, now, "UTC".to_owned())?;
    assert_eq!(short.bucket_kind, FfiBucketKind::Hour);
    assert_eq!(short.buckets.len(), 2);
    assert_eq!(
        short.buckets[1].start_ms - short.buckets[0].start_ms,
        MS_PER_HOUR
    );

    let long = engine.activity(now - 5 * MS_PER_DAY, now, "UTC".to_owned())?;
    assert_eq!(long.bucket_kind, FfiBucketKind::Day);
    assert_eq!(long.buckets.len(), 6, "the partial first day counts");
    assert!(long.buckets[0].end_ms - long.buckets[0].start_ms < MS_PER_DAY);
    assert_eq!(
        long.buckets[1].end_ms - long.buckets[1].start_ms,
        MS_PER_DAY
    );
    Ok(())
}

#[test]
fn day_buckets_follow_local_midnight_across_a_fall_back_week() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let span = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        None,
        None,
        FALL_BACK_WEEK_START_MS,
    )?;
    engine.end_span(span, FALL_BACK_WEEK_END_MS)?;

    let week = engine.activity(
        FALL_BACK_WEEK_START_MS,
        FALL_BACK_WEEK_END_MS,
        NEW_YORK.to_owned(),
    )?;

    assert_eq!(week.bucket_kind, FfiBucketKind::Day);
    assert_eq!(week.buckets.len(), 7);
    assert_eq!(week.buckets[0].start_ms, FALL_BACK_WEEK_START_MS);
    assert_eq!(
        week.buckets[0].end_ms,
        FALL_BACK_WEEK_START_MS + 25 * MS_PER_HOUR
    );
    assert_eq!(week.buckets[0].reading_ms, 25 * MS_PER_HOUR);
    assert_eq!(week.buckets[1].reading_ms, MS_PER_DAY);
    assert_eq!(week.buckets[6].end_ms, FALL_BACK_WEEK_END_MS);
    assert_eq!(week.total_ms, 7 * MS_PER_DAY + MS_PER_HOUR);
    Ok(())
}

#[test]
fn a_timeline_above_the_bucket_limit_is_invalid_input() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();

    let error = engine.timeline(0, MS_PER_HOUR, 4_097).unwrap_err();

    assert!(matches!(error, ErstError::InvalidInput { .. }), "{error}");
    Ok(())
}
