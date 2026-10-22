#![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

use super::parse;
use crate::time::{MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE, days_from_civil, new_york_2026};

/// A zone with the same offset everywhere, in minutes east of UTC.
fn fixed(minutes: i64) -> impl Fn(i64) -> i64 {
    move |_| minutes * MS_PER_MINUTE
}

const OCT_15_2026_0210Z: i64 = 1_792_029_600_000;
const OCT_14_MIDNIGHT_UTC_MINUS_5: i64 = 1_791_954_000_000;
const OCT_15_MIDNIGHT_UTC_MINUS_5: i64 = 1_792_040_400_000;
const OCT_13_MIDNIGHT_UTC_MINUS_5: i64 = 1_791_867_600_000;
const OCT_1_MIDNIGHT_UTC_MINUS_5: i64 = 1_790_830_800_000;
const OCT_20_MIDNIGHT_UTC_MINUS_5: i64 = 1_792_472_400_000;
const OCT_21_MIDNIGHT_UTC_MINUS_5: i64 = 1_792_558_800_000;

#[test]
fn empty_input_is_empty() {
    let query = parse("", 0, fixed(0));
    assert!(query.is_empty());
    assert_eq!(query.fts_match(), None);
}

#[test]
fn keeps_plain_terms_as_typed() {
    let query = parse("PINN Lake", 0, fixed(0));
    assert_eq!(query.terms, vec!["PINN", "Lake"]);
    assert!(query.phrases.is_empty());
    assert_eq!(query.fts_match().as_deref(), Some("\"PINN\" \"Lake\"*"));
    assert!(!query.is_empty());
}

#[test]
fn quoted_phrases_are_separate_and_get_no_prefix_marker() {
    let query = parse("\"hello world\"", 0, fixed(0));
    assert!(query.terms.is_empty());
    assert_eq!(query.phrases, vec!["hello world"]);
    assert_eq!(query.fts_match().as_deref(), Some("\"hello world\""));
}

#[test]
fn terms_and_phrases_are_joined() {
    let query = parse("pinn \"hello world\"", 0, fixed(0));
    assert_eq!(query.terms, vec!["pinn"]);
    assert_eq!(query.phrases, vec!["hello world"]);
    assert_eq!(
        query.fts_match().as_deref(),
        Some("\"pinn\"* \"hello world\"")
    );
}

#[test]
fn double_quotes_inside_values_are_escaped() {
    let query = parse("\"say \\\"hi\\\"\"", 0, fixed(0));
    assert_eq!(query.phrases, vec!["say \"hi\""]);
    assert_eq!(query.fts_match().as_deref(), Some("\"say \"\"hi\"\"\""));
}

#[test]
fn bare_quotes_in_a_term_are_escaped() {
    let query = parse("he\"llo", 0, fixed(0));
    assert_eq!(query.terms, vec!["he\"llo"]);
    assert_eq!(query.fts_match().as_deref(), Some("\"he\"\"llo\"*"));
}

#[test]
fn parses_an_unquoted_app_filter() {
    let query = parse("app:Safari pinn", 0, fixed(0));
    assert_eq!(query.app.as_deref(), Some("Safari"));
    assert_eq!(query.terms, vec!["pinn"]);
    assert_eq!(query.fts_match().as_deref(), Some("\"pinn\"*"));
    assert!(!query.is_empty());
}

#[test]
fn parses_a_quoted_app_filter() {
    let query = parse("app:\"Visual Studio Code\" budget", 0, fixed(0));
    assert_eq!(query.app.as_deref(), Some("Visual Studio Code"));
    assert_eq!(query.terms, vec!["budget"]);
}

#[test]
fn app_filter_values_may_contain_colons() {
    let query = parse("app:\"Foo:Bar\"", 0, fixed(0));
    assert_eq!(query.app.as_deref(), Some("Foo:Bar"));
    assert!(query.terms.is_empty());
}

#[test]
fn empty_app_filter_stays_a_term() {
    let query = parse("app:", 0, fixed(0));
    assert_eq!(query.app, None);
    assert_eq!(query.terms, vec!["app:"]);
}

#[test]
fn unknown_prefixes_stay_terms() {
    let query = parse("foo:bar", 0, fixed(0));
    assert_eq!(query.terms, vec!["foo:bar"]);
}

#[test]
fn parses_since_and_until_with_a_negative_offset() {
    let query = parse("since:2026-10-01 until:2026-10-20", 0, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_1_MIDNIGHT_UTC_MINUS_5));
    assert_eq!(query.until_ms, Some(OCT_21_MIDNIGHT_UTC_MINUS_5));
    assert!(query.terms.is_empty());
    assert!(query.phrases.is_empty());
    assert_eq!(query.fts_match(), None);
    assert!(!query.is_empty());
}

#[test]
fn invalid_dates_stay_terms() {
    let query = parse(
        "since:2026-02-30 until:2026-13-01 since:2026-1-01",
        0,
        fixed(0),
    );
    assert_eq!(query.since_ms, None);
    assert_eq!(query.until_ms, None);
    assert_eq!(
        query.terms,
        vec!["since:2026-02-30", "until:2026-13-01", "since:2026-1-01"]
    );
}

#[test]
fn leap_dates_are_valid_for_until() {
    let query = parse("until:2024-02-29", 0, fixed(0));
    assert_eq!(query.until_ms, Some(1_709_251_200_000));
}

#[test]
fn today_uses_the_local_day_with_a_negative_offset() {
    let query = parse("today", OCT_15_2026_0210Z, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_14_MIDNIGHT_UTC_MINUS_5));
    assert_eq!(query.until_ms, Some(OCT_15_MIDNIGHT_UTC_MINUS_5));
    assert_eq!(query.terms, Vec::<String>::new());
    assert!(!query.is_empty());
}

#[test]
fn yesterday_ends_at_todays_local_midnight() {
    let query = parse("yesterday", OCT_15_2026_0210Z, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_13_MIDNIGHT_UTC_MINUS_5));
    assert_eq!(query.until_ms, Some(OCT_14_MIDNIGHT_UTC_MINUS_5));
}

#[test]
fn day_keywords_combine_with_terms() {
    let query = parse("today pinn", OCT_15_2026_0210Z, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_14_MIDNIGHT_UTC_MINUS_5));
    assert_eq!(query.terms, vec!["pinn"]);
    assert_eq!(query.fts_match().as_deref(), Some("\"pinn\"*"));
}

#[test]
fn day_keywords_are_case_insensitive() {
    let query = parse("TODAY", OCT_15_2026_0210Z, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_14_MIDNIGHT_UTC_MINUS_5));
}

#[test]
fn quoted_day_keywords_stay_phrases() {
    let query = parse("\"today\"", OCT_15_2026_0210Z, fixed(-300));
    assert_eq!(query.since_ms, None);
    assert_eq!(query.phrases, vec!["today"]);
}

#[test]
fn a_later_date_filter_replaces_an_earlier_one() {
    let query = parse("since:2026-10-01 since:2026-10-20", 0, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_20_MIDNIGHT_UTC_MINUS_5));
}

#[test]
fn prefixed_dates_support_quoted_values() {
    let query = parse("since:\"2026-10-01\"", 0, fixed(-300));
    assert_eq!(query.since_ms, Some(OCT_1_MIDNIGHT_UTC_MINUS_5));
}

#[test]
fn unterminated_quotes_take_the_rest() {
    let query = parse("\"hello world", 0, fixed(0));
    assert_eq!(query.phrases, vec!["hello world"]);
}

#[test]
fn whitespace_only_input_is_empty() {
    let query = parse("  \t \n ", 0, fixed(0));
    assert!(query.is_empty());
    assert_eq!(query.fts_match(), None);
}

#[test]
fn empty_values_are_not_quoted_into_the_match_expression() {
    let query = parse("\"\"", 0, fixed(0));
    assert!(query.phrases.is_empty());
    assert_eq!(query.fts_match(), None);
    assert!(query.is_empty());
}

/// Unix milliseconds at `hour` UTC on a 2026 date.
fn utc(month: u32, day: u32, hour: i64) -> i64 {
    days_from_civil(2026, month, day) * MS_PER_DAY + hour * MS_PER_HOUR
}

#[test]
fn today_on_the_fall_back_day_starts_at_edt_midnight() {
    // 2026-11-01T15:00Z is 10:00 EST, on the day New York repeats an hour.
    let query = parse("today", utc(11, 1, 15), new_york_2026);
    assert_eq!(query.since_ms, Some(utc(11, 1, 4)));
    assert_eq!(query.until_ms, Some(utc(11, 2, 5)));
    let length_ms = query.until_ms.unwrap() - query.since_ms.unwrap();
    assert_eq!(length_ms, 25 * MS_PER_HOUR);
}

#[test]
fn yesterday_after_the_fall_back_day_starts_at_edt_midnight() {
    let query = parse("yesterday", utc(11, 2, 15), new_york_2026);
    assert_eq!(query.since_ms, Some(utc(11, 1, 4)));
    assert_eq!(query.until_ms, Some(utc(11, 2, 5)));
}

#[test]
fn until_date_on_the_fall_back_day_includes_the_whole_day() {
    let query = parse("until:2026-11-01", utc(11, 2, 15), new_york_2026);
    assert_eq!(query.until_ms, Some(utc(11, 2, 5)));
}

#[test]
fn yesterday_after_the_spring_forward_day_starts_at_est_midnight() {
    // 2026-03-09T15:00Z is 11:00 EDT, after New York moved its clock forward.
    let query = parse("yesterday", utc(3, 9, 15), new_york_2026);
    assert_eq!(query.since_ms, Some(utc(3, 8, 5)));
    assert_eq!(query.until_ms, Some(utc(3, 9, 4)));
}

#[test]
fn since_date_on_the_spring_forward_day_starts_at_est_midnight() {
    let query = parse("since:2026-03-08", utc(3, 9, 15), new_york_2026);
    assert_eq!(query.since_ms, Some(utc(3, 8, 5)));
}
