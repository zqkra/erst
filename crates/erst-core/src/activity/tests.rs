#![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

use super::{ActivityBucket, ActivitySummary, AppTotal, BucketKind, Category, SiteTotal, Span};
use crate::error::CoreError;
use crate::time::{MAX_BUCKETS, MS_PER_DAY, MS_PER_HOUR, TimeRange, new_york_2026};
use crate::track::url_host;

mod categories;

const MINUTE: i64 = 60_000;

fn span(bundle_id: &str, started_at: i64, ended_at: i64) -> Span {
    Span {
        bundle_id: String::from(bundle_id),
        url: None,
        started_at,
        ended_at,
    }
}

fn range(start_ms: i64, end_ms: i64) -> TimeRange {
    TimeRange::new(start_ms, end_ms).unwrap()
}

fn buckets(summary: &ActivitySummary) -> Vec<ActivityBucket> {
    summary.buckets.clone()
}

fn summarize(spans: &[Span], range: TimeRange) -> ActivitySummary {
    super::summarize(spans, range, |_| 0).unwrap()
}

fn bucket(start_ms: i64, building: i64, reading: i64, talking: i64, other: i64) -> ActivityBucket {
    ActivityBucket {
        start_ms,
        end_ms: start_ms + MS_PER_HOUR,
        building_ms: building,
        reading_ms: reading,
        talking_ms: talking,
        other_ms: other,
    }
}

#[test]
fn summarize_without_spans_is_empty_but_has_buckets() {
    let summary = summarize(&[], range(0, MS_PER_HOUR));
    assert_eq!(summary.total_ms, 0);
    assert!(summary.apps.is_empty());
    assert!(summary.websites.is_empty());
    assert_eq!(
        summary.categories,
        [
            (Category::Building, 0),
            (Category::Reading, 0),
            (Category::Talking, 0),
            (Category::Other, 0),
        ]
    );
    assert_eq!(buckets(&summary), vec![bucket(0, 0, 0, 0, 0)]);
}

#[test]
fn summarize_empty_range_has_no_buckets() {
    let summary = summarize(&[span("com.apple.Safari", 0, MS_PER_HOUR)], range(0, 0));
    assert_eq!(summary.total_ms, 0);
    assert!(summary.buckets.is_empty());
    assert!(summary.apps.is_empty());
}

#[test]
fn clips_spans_to_the_range() {
    let summary = summarize(
        &[span("dev.zed.Zed", -10 * MINUTE, 20 * MINUTE)],
        range(0, 10 * MINUTE),
    );
    assert_eq!(summary.total_ms, 10 * MINUTE);
    assert_eq!(
        summary.apps,
        vec![AppTotal {
            bundle_id: String::from("dev.zed.Zed"),
            ms: 10 * MINUTE,
        }]
    );
}

#[test]
fn ignores_spans_outside_the_range() {
    let summary = summarize(
        &[
            span("com.apple.Safari", -10 * MINUTE, -MINUTE),
            span("com.apple.Safari", 20 * MINUTE, 30 * MINUTE),
        ],
        range(0, 10 * MINUTE),
    );
    assert_eq!(summary.total_ms, 0);
    assert!(summary.apps.is_empty());
}

#[test]
fn ignores_zero_length_spans() {
    let summary = summarize(
        &[span("com.apple.Safari", 5_000, 5_000)],
        range(0, MS_PER_HOUR),
    );
    assert_eq!(summary.total_ms, 0);
    assert!(summary.apps.is_empty());
    assert_eq!(buckets(&summary), vec![bucket(0, 0, 0, 0, 0)]);
}

#[test]
fn splits_a_span_across_hour_boundaries() {
    let summary = summarize(
        &[span("com.apple.Safari", 0, MS_PER_HOUR + MS_PER_HOUR / 2)],
        range(0, 2 * MS_PER_HOUR),
    );
    assert_eq!(summary.total_ms, MS_PER_HOUR + MS_PER_HOUR / 2);
    assert_eq!(
        buckets(&summary),
        vec![
            bucket(0, 0, MS_PER_HOUR, 0, 0),
            bucket(MS_PER_HOUR, 0, MS_PER_HOUR / 2, 0, 0),
        ]
    );
}

#[test]
fn hour_buckets_start_at_the_range_start() {
    let start = 30 * MINUTE;
    let summary = summarize(
        &[span("dev.zed.Zed", 0, 3 * MS_PER_HOUR)],
        range(start, start + 2 * MS_PER_HOUR),
    );
    assert_eq!(summary.total_ms, 2 * MS_PER_HOUR);
    assert_eq!(
        buckets(&summary),
        vec![
            bucket(start, MS_PER_HOUR, 0, 0, 0),
            bucket(start + MS_PER_HOUR, MS_PER_HOUR, 0, 0, 0),
        ]
    );
}

#[test]
fn clips_a_span_that_crosses_hour_and_range_boundaries() {
    let summary = summarize(
        &[span("com.apple.MobileSMS", -MS_PER_HOUR, 3 * MS_PER_HOUR)],
        range(0, 2 * MS_PER_HOUR),
    );
    assert_eq!(summary.total_ms, 2 * MS_PER_HOUR);
    assert_eq!(
        buckets(&summary),
        vec![
            bucket(0, 0, 0, MS_PER_HOUR, 0),
            bucket(MS_PER_HOUR, 0, 0, MS_PER_HOUR, 0),
        ]
    );
    assert_eq!(summary.categories[2], (Category::Talking, 2 * MS_PER_HOUR));
}

#[test]
fn covers_a_partial_last_hour() {
    let summary = summarize(
        &[span("com.apple.Safari", 0, MS_PER_HOUR * 5 / 2)],
        range(0, MS_PER_HOUR * 5 / 2),
    );
    assert_eq!(
        buckets(&summary),
        vec![
            bucket(0, 0, MS_PER_HOUR, 0, 0),
            bucket(MS_PER_HOUR, 0, MS_PER_HOUR, 0, 0),
            ActivityBucket {
                start_ms: 2 * MS_PER_HOUR,
                end_ms: MS_PER_HOUR * 5 / 2,
                reading_ms: MS_PER_HOUR / 2,
                ..ActivityBucket::default()
            },
        ]
    );
}

#[test]
fn apps_are_sorted_by_time_then_bundle_id() {
    let summary = summarize(
        &[
            span("com.apple.Safari", 0, MS_PER_HOUR),
            span("dev.zed.Zed", MS_PER_HOUR, 3 * MS_PER_HOUR),
            span("com.google.Chrome", 3 * MS_PER_HOUR, 4 * MS_PER_HOUR),
        ],
        range(0, 4 * MS_PER_HOUR),
    );
    assert_eq!(
        summary.apps,
        vec![
            AppTotal {
                bundle_id: String::from("dev.zed.Zed"),
                ms: 2 * MS_PER_HOUR,
            },
            AppTotal {
                bundle_id: String::from("com.apple.Safari"),
                ms: MS_PER_HOUR,
            },
            AppTotal {
                bundle_id: String::from("com.google.Chrome"),
                ms: MS_PER_HOUR,
            },
        ]
    );
}

#[test]
fn accumulates_repeated_apps() {
    let summary = summarize(
        &[
            span("com.apple.Safari", 0, MINUTE),
            span("com.apple.Safari", 2 * MINUTE, 4 * MINUTE),
        ],
        range(0, MS_PER_HOUR),
    );
    assert_eq!(
        summary.apps,
        vec![AppTotal {
            bundle_id: String::from("com.apple.Safari"),
            ms: 3 * MINUTE,
        }]
    );
}

fn url_span(url: &str, started_at: i64, ended_at: i64) -> Span {
    Span {
        bundle_id: String::from("com.apple.Safari"),
        url: Some(String::from(url)),
        started_at,
        ended_at,
    }
}

#[test]
fn websites_are_normalized_and_sorted() {
    let summary = summarize(
        &[
            url_span("https://Example.COM:443/Path?q=1", 0, MINUTE),
            url_span("http://www.example.com/other", MINUTE, 3 * MINUTE),
            url_span("https://news.ycombinator.com/", 3 * MINUTE, 4 * MINUTE),
        ],
        range(0, MS_PER_HOUR),
    );
    assert_eq!(
        summary.websites,
        vec![
            SiteTotal {
                host: String::from("example.com"),
                ms: 3 * MINUTE,
            },
            SiteTotal {
                host: String::from("news.ycombinator.com"),
                ms: MINUTE,
            },
        ]
    );
}

#[test]
fn websites_with_the_same_total_are_sorted_by_host() {
    let summary = summarize(
        &[
            url_span("https://zeta.example/", MINUTE, 2 * MINUTE),
            url_span("https://alpha.example/", 0, MINUTE),
        ],
        range(0, MS_PER_HOUR),
    );
    assert_eq!(
        summary.websites,
        vec![
            SiteTotal {
                host: String::from("alpha.example"),
                ms: MINUTE,
            },
            SiteTotal {
                host: String::from("zeta.example"),
                ms: MINUTE,
            },
        ]
    );
}

#[test]
fn category_totals_follow_enum_order() {
    let summary = summarize(
        &[
            span("dev.zed.Zed", 0, MINUTE),
            span("com.apple.Safari", MINUTE, 3 * MINUTE),
            span("com.apple.mail", 3 * MINUTE, 6 * MINUTE),
            span("com.example.Other", 6 * MINUTE, 10 * MINUTE),
        ],
        range(0, MS_PER_HOUR),
    );
    assert_eq!(
        summary.categories,
        [
            (Category::Building, MINUTE),
            (Category::Reading, 2 * MINUTE),
            (Category::Talking, 3 * MINUTE),
            (Category::Other, 4 * MINUTE),
        ]
    );
    assert_eq!(summary.total_ms, 10 * MINUTE);
}

#[test]
fn hour_totals_match_the_summary_total() {
    let summary = summarize(
        &[
            span("dev.zed.Zed", 0, 90 * MINUTE),
            span("com.apple.Safari", 30 * MINUTE, 150 * MINUTE),
            span("com.apple.mail", 200 * MINUTE, 210 * MINUTE),
        ],
        range(0, 240 * MINUTE),
    );
    let hour_total: i64 = summary
        .buckets
        .iter()
        .map(|hour| hour.building_ms + hour.reading_ms + hour.talking_ms + hour.other_ms)
        .sum();
    assert_eq!(hour_total, summary.total_ms);
    // Safari overlaps Zed from 30 to 90 minutes, so the first 60 minutes of Safari do not count.
    assert_eq!(summary.total_ms, (90 + 60 + 10) * MINUTE);
    assert_eq!(summary.buckets.len(), 4);
}

#[test]
fn url_hosts_handle_scheme_case_port_and_path() {
    assert_eq!(
        url_host("https://Example.COM:8443/path?q=1#frag").as_deref(),
        Some("example.com")
    );
    assert_eq!(
        url_host("HTTP://WWW.Example.com").as_deref(),
        Some("example.com")
    );
    assert_eq!(
        url_host("https://user:pass@example.com:443/x").as_deref(),
        Some("example.com")
    );
    assert_eq!(url_host("https://[::1]:8080/x").as_deref(), Some("::1"));
}

#[test]
fn url_hosts_handle_schemeless_and_empty_values() {
    assert_eq!(url_host("example.com/path").as_deref(), Some("example.com"));
    assert_eq!(url_host("www.example.com").as_deref(), Some("example.com"));
    assert_eq!(url_host(""), None);
    assert_eq!(url_host("   "), None);
    assert_eq!(url_host("https://"), None);
    assert_eq!(url_host("www."), None);
    assert_eq!(url_host("file:///Users/me/Desktop"), None);
}

fn app_ms(summary: &ActivitySummary, bundle_id: &str) -> i64 {
    summary
        .apps
        .iter()
        .find(|app| app.bundle_id == bundle_id)
        .map_or(0, |app| app.ms)
}

#[test]
fn overlapping_spans_count_each_moment_once() {
    // [0, 300) and [200, 1000) share [200, 300), so the screen showed 1000 ms, not 1100.
    let spans = [span("com.a", 0, 300), span("com.a", 200, 1_000)];
    let summary = summarize(&spans, range(0, 1_000));
    assert_eq!(summary.total_ms, 1_000);
    assert_eq!(app_ms(&summary, "com.a"), 1_000);
    assert_eq!(summary.categories[3], (Category::Other, 1_000));
    assert_eq!(buckets(&summary)[0].other_ms, 1_000);
}

#[test]
fn overlaps_between_apps_go_to_the_app_that_started_first() {
    let spans = [
        span("com.apple.Safari", 0, 600),
        span("com.apple.dt.Xcode", 400, 1_000),
    ];
    let summary = summarize(&spans, range(0, 1_000));
    assert_eq!(summary.total_ms, 1_000);
    assert_eq!(app_ms(&summary, "com.apple.Safari"), 600);
    assert_eq!(app_ms(&summary, "com.apple.dt.Xcode"), 400);
    let app_total: i64 = summary.apps.iter().map(|app| app.ms).sum();
    assert_eq!(app_total, summary.total_ms);
}

#[test]
fn a_span_nested_inside_another_adds_nothing() {
    let spans = [span("com.a", 0, 1_000), span("com.a", 100, 200)];
    assert_eq!(summarize(&spans, range(0, 1_000)).total_ms, 1_000);
}

#[test]
fn touching_spans_add_up_without_double_counting_the_edge() {
    let spans = [span("com.a", 0, 300), span("com.a", 300, 1_000)];
    assert_eq!(summarize(&spans, range(0, 1_000)).total_ms, 1_000);
}

#[test]
fn overlapping_spans_are_not_double_counted_in_a_bucket() {
    let spans = [
        span("com.apple.Safari", 0, 300),
        span("com.apple.Safari", 200, 1_000),
    ];
    let summary = summarize(&spans, range(0, MS_PER_HOUR));
    assert_eq!(buckets(&summary)[0].reading_ms, 1_000);
    assert_eq!(summary.categories[1], (Category::Reading, 1_000));
}

#[test]
fn overlap_across_an_hour_boundary_is_split_once() {
    let edge = MS_PER_HOUR;
    let spans = [
        span("com.a", edge - 100, edge + 100),
        span("com.a", edge - 50, edge + 50),
    ];
    let summary = summarize(&spans, range(0, 2 * MS_PER_HOUR));
    assert_eq!(buckets(&summary)[0].other_ms, 100);
    assert_eq!(buckets(&summary)[1].other_ms, 100);
    assert_eq!(summary.total_ms, 200);
}

#[test]
fn a_range_of_three_days_gets_one_bucket_per_hour() {
    let summary = summarize(&[], range(0, 3 * MS_PER_DAY));
    assert_eq!(summary.kind, BucketKind::Hour);
    assert_eq!(summary.buckets.len(), 72);
}

#[test]
fn a_longer_range_gets_one_bucket_per_day() {
    let summary = summarize(&[], range(0, 4 * MS_PER_DAY));
    assert_eq!(summary.kind, BucketKind::Day);
    assert_eq!(summary.buckets.len(), 4);
    assert_eq!(summary.buckets[3].start_ms, 3 * MS_PER_DAY);
    assert_eq!(summary.buckets[3].end_ms, 4 * MS_PER_DAY);
}

#[test]
fn day_buckets_split_a_span_at_the_day_boundary() {
    let spans = [span(
        "com.apple.Safari",
        MS_PER_DAY - MS_PER_HOUR,
        MS_PER_DAY + 2 * MS_PER_HOUR,
    )];
    let summary = summarize(&spans, range(0, 4 * MS_PER_DAY));
    assert_eq!(buckets(&summary)[0].reading_ms, MS_PER_HOUR);
    assert_eq!(buckets(&summary)[1].reading_ms, 2 * MS_PER_HOUR);
    assert_eq!(summary.total_ms, 3 * MS_PER_HOUR);
}

#[test]
fn an_all_time_range_is_rejected_before_any_bucket_is_allocated() {
    // From year 1 to 2026-10-20 is about 730,000 days.
    let all_time = TimeRange::new(-62_135_596_800_000, 1_792_497_600_000).unwrap();
    let error = super::summarize(&[], all_time, |_| 0).unwrap_err();
    assert!(matches!(error, CoreError::TooManyBuckets { count } if count > 700_000));
}

#[test]
fn the_bucket_limit_is_inclusive() {
    let at_limit = TimeRange::new(0, 4_096 * MS_PER_DAY).unwrap();
    assert_eq!(
        super::summarize(&[], at_limit, |_| 0)
            .unwrap()
            .buckets
            .len(),
        MAX_BUCKETS
    );
    let over_limit = TimeRange::new(0, 4_097 * MS_PER_DAY).unwrap();
    assert_eq!(
        super::summarize(&[], over_limit, |_| 0).unwrap_err(),
        CoreError::TooManyBuckets { count: 4_097 }
    );
}

#[test]
fn a_fall_back_week_gets_local_day_buckets() {
    // 2026-11-01 00:00 EDT to 2026-11-08 00:00 EST, the week New York repeats an hour.
    let week = TimeRange::new(1_793_505_600_000, 1_794_114_000_000).unwrap();
    let summary = super::summarize(
        &[span("com.apple.Safari", week.start_ms, week.end_ms)],
        week,
        new_york_2026,
    )
    .unwrap();
    assert_eq!(summary.kind, BucketKind::Day);
    assert_eq!(summary.buckets.len(), 7);
    assert_eq!(summary.buckets[0].start_ms, week.start_ms);
    assert_eq!(
        summary.buckets[0].end_ms, 1_793_595_600_000,
        "2026-11-02T05:00Z"
    );
    assert_eq!(summary.buckets[0].reading_ms, 25 * MS_PER_HOUR);
    assert_eq!(summary.buckets[1].reading_ms, MS_PER_DAY);
    assert_eq!(summary.total_ms, 7 * MS_PER_DAY + MS_PER_HOUR);
    assert_eq!(
        summary
            .buckets
            .iter()
            .map(|bucket| bucket.reading_ms)
            .sum::<i64>(),
        summary.total_ms
    );
}

#[test]
fn a_spring_forward_week_gets_local_day_buckets() {
    // 2026-03-08 00:00 EST to 2026-03-15 00:00 EDT, the week New York skips an hour.
    let week = TimeRange::new(1_772_946_000_000, 1_773_547_200_000).unwrap();
    let summary = super::summarize(&[], week, new_york_2026).unwrap();
    assert_eq!(summary.kind, BucketKind::Day);
    assert_eq!(summary.buckets.len(), 7);
    assert_eq!(summary.buckets[0].end_ms - week.start_ms, 23 * MS_PER_HOUR);
    assert_eq!(summary.buckets[6].end_ms, week.end_ms);
}
