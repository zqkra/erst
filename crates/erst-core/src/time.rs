//! Timestamps, half-open time ranges, civil dates, and local days.
//!
//! A local day starts at local midnight. The UTC offset at that instant can
//! differ from the offset at the query time when a daylight saving change falls
//! inside the day, so the functions here take an offset resolver: a function
//! from an instant to its UTC offset in milliseconds, positive east of
//! Greenwich.

use std::time::{SystemTime, UNIX_EPOCH};

/// Milliseconds in one minute.
pub const MS_PER_MINUTE: i64 = 60_000;
/// Milliseconds in one hour.
pub const MS_PER_HOUR: i64 = 3_600_000;
/// Milliseconds in one day.
pub const MS_PER_DAY: i64 = 86_400_000;

/// Most buckets one heat strip or activity report may hold.
pub const MAX_BUCKETS: usize = 4_096;

/// Extra passes that refine a local midnight after its first estimate.
const MIDNIGHT_REFINEMENTS: usize = 3;

/// A half-open instant range `[start_ms, end_ms)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TimeRange {
    /// Inclusive start in Unix milliseconds.
    pub start_ms: i64,
    /// Exclusive end in Unix milliseconds.
    pub end_ms: i64,
}

impl TimeRange {
    /// Creates a range, or `None` when `end_ms < start_ms`.
    pub fn new(start_ms: i64, end_ms: i64) -> Option<Self> {
        (end_ms >= start_ms).then_some(Self { start_ms, end_ms })
    }

    /// Length of the range in milliseconds.
    pub fn duration_ms(&self) -> i64 {
        self.end_ms.saturating_sub(self.start_ms)
    }

    /// Whether the range covers no instants.
    pub fn is_empty(&self) -> bool {
        self.end_ms <= self.start_ms
    }

    /// Whether `ms` lies inside the half-open range.
    pub fn contains(&self, ms: i64) -> bool {
        self.start_ms <= ms && ms < self.end_ms
    }
}

/// The wall clock in Unix milliseconds, negative before 1970.
///
/// This is the only clock read in `erst-core`. Every other function takes the
/// time as an argument.
pub fn now_ms() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => i64::try_from(elapsed.as_millis()).unwrap_or(i64::MAX),
        Err(error) => -i64::try_from(error.duration().as_millis()).unwrap_or(i64::MAX),
    }
}

/// Days since 1970-01-01 for a proleptic Gregorian date.
///
/// `month` uses 1 for January. This is Howard Hinnant's `days_from_civil`
/// algorithm. The result is only meaningful for a valid date; user input
/// should go through [`local_day_of_text`], which validates it.
pub fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let month = i128::from(month);
    let day = i128::from(day);
    let year = i128::from(year);
    let adjusted_year = if month <= 2 { year - 1 } else { year };
    let era = if adjusted_year >= 0 {
        adjusted_year
    } else {
        adjusted_year - 399
    } / 400;
    let year_of_era = adjusted_year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146_097 + day_of_era - 719_468;
    i64::try_from(days).unwrap_or(if days < 0 { i64::MIN } else { i64::MAX })
}

/// The local day that contains `now_ms`, from its local midnight to the next.
pub fn local_day_containing(now_ms: i64, offset_ms_at: impl Fn(i64) -> i64) -> TimeRange {
    let local_ms = now_ms.saturating_add(offset_ms_at(now_ms));
    local_day(local_ms.div_euclid(MS_PER_DAY), now_ms, &offset_ms_at)
}

/// The local day named by `YYYY-MM-DD`, or `None` when the text is not a real date.
pub fn local_day_of_text(text: &str, offset_ms_at: impl Fn(i64) -> i64) -> Option<TimeRange> {
    let (year, month, day) = parse_date(text)?;
    if !is_valid_date(year, month, day) {
        return None;
    }
    let index = days_from_civil(year, month, day);
    Some(local_day(
        index,
        index.saturating_mul(MS_PER_DAY),
        &offset_ms_at,
    ))
}

/// Parses `YYYY-MM-DD` into its parts without checking that the date exists.
fn parse_date(value: &str) -> Option<(i64, u32, u32)> {
    if !value.is_ascii() || value.len() != 10 {
        return None;
    }
    let bytes = value.as_bytes();
    if bytes[4] != b'-' || bytes[7] != b'-' {
        return None;
    }
    if bytes
        .iter()
        .enumerate()
        .any(|(index, byte)| index != 4 && index != 7 && !byte.is_ascii_digit())
    {
        return None;
    }
    let year = value.get(0..4)?.parse::<i64>().ok()?;
    let month = value.get(5..7)?.parse::<u32>().ok()?;
    let day = value.get(8..10)?.parse::<u32>().ok()?;
    Some((year, month, day))
}

/// How many local days the half-open range touches, zero for an empty range.
///
/// A range that starts and ends in the same local day has one bucket, and a
/// range that ends exactly at a local midnight does not count the day after it.
pub fn local_day_count(range: TimeRange, offset_ms_at: impl Fn(i64) -> i64) -> u64 {
    if range.is_empty() {
        return 0;
    }
    let first = local_day_index(range.start_ms, &offset_ms_at);
    let last = local_day_index(range.end_ms.saturating_sub(1), &offset_ms_at);
    u64::try_from(last.saturating_sub(first).saturating_add(1)).unwrap_or(u64::MAX)
}

/// Buckets of whole local days covering `range`.
///
/// The first bucket starts at `range.start_ms`, every later one at the local
/// midnight that ends the previous one, and the last ends at `range.end_ms`.
/// A day with a daylight saving change is 23 or 25 hours long, so the buckets do
/// not all have the same width.
pub fn local_day_buckets(range: TimeRange, offset_ms_at: impl Fn(i64) -> i64) -> Vec<TimeRange> {
    let count = usize::try_from(local_day_count(range, &offset_ms_at)).unwrap_or(0);
    let mut buckets = Vec::with_capacity(count);
    let mut start_ms = range.start_ms;
    for index in 0..count {
        let end_ms = if index + 1 == count {
            range.end_ms
        } else {
            next_local_midnight(start_ms, &offset_ms_at).min(range.end_ms)
        };
        // A zone that skipped a whole local date (Samoa in 2011) can resolve a
        // midnight before the bucket start. Keep the buckets ordered, so an
        // empty bucket appears where a local day never happened.
        let end_ms = end_ms.max(start_ms);
        buckets.push(TimeRange { start_ms, end_ms });
        start_ms = end_ms;
    }
    buckets
}

/// The index of the local day containing `at_ms`, as days since the epoch.
fn local_day_index(at_ms: i64, offset_ms_at: &impl Fn(i64) -> i64) -> i64 {
    at_ms
        .saturating_add(offset_ms_at(at_ms))
        .div_euclid(MS_PER_DAY)
}

/// The instant of the next local midnight strictly after `at_ms`.
fn next_local_midnight(at_ms: i64, offset_ms_at: &impl Fn(i64) -> i64) -> i64 {
    let day = local_day_index(at_ms, offset_ms_at).saturating_add(1);
    midnight_of(day, at_ms, offset_ms_at)
}

/// The local day with index `day` (days since the epoch on the local wall clock).
fn local_day<F: Fn(i64) -> i64>(day: i64, hint_ms: i64, offset_ms_at: &F) -> TimeRange {
    let start_ms = midnight_of(day, hint_ms, offset_ms_at);
    let next_start_ms = midnight_of(day.saturating_add(1), start_ms, offset_ms_at);
    TimeRange {
        start_ms,
        end_ms: next_start_ms.max(start_ms),
    }
}

/// The instant at which the local wall clock reads midnight of `day`.
///
/// The first estimate uses the offset at `hint_ms`. A daylight saving change
/// near midnight can make the offset at the answer differ from the offset at
/// the hint, so the estimate is refined until it stops moving.
fn midnight_of<F: Fn(i64) -> i64>(day: i64, hint_ms: i64, offset_ms_at: &F) -> i64 {
    let wall_ms = day.saturating_mul(MS_PER_DAY);
    let mut instant_ms = wall_ms.saturating_sub(offset_ms_at(hint_ms));
    for _ in 0..MIDNIGHT_REFINEMENTS {
        let refined_ms = wall_ms.saturating_sub(offset_ms_at(instant_ms));
        if refined_ms == instant_ms {
            break;
        }
        instant_ms = refined_ms;
    }
    instant_ms
}

fn is_valid_date(year: i64, month: u32, day: u32) -> bool {
    (1..=12).contains(&month) && day >= 1 && day <= days_in_month(year, month)
}

fn days_in_month(year: i64, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => 0,
    }
}

fn is_leap_year(year: i64) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

/// `America/New_York` for 2026: EST, then EDT from 2026-03-08 07:00Z, then EST
/// again from 2026-11-01 06:00Z.
#[cfg(test)]
pub(crate) fn new_york_2026(at_ms: i64) -> i64 {
    let spring_ms = days_from_civil(2026, 3, 8) * MS_PER_DAY + 7 * MS_PER_HOUR;
    let fall_ms = days_from_civil(2026, 11, 1) * MS_PER_DAY + 6 * MS_PER_HOUR;
    let offset_hours = if (spring_ms..fall_ms).contains(&at_ms) {
        -4
    } else {
        -5
    };
    offset_hours * MS_PER_HOUR
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

    use super::{
        MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE, TimeRange, days_from_civil, local_day_buckets,
        local_day_containing, local_day_count, local_day_of_text, new_york_2026, now_ms,
    };

    fn fixed(minutes: i64) -> impl Fn(i64) -> i64 {
        move |_| minutes * MS_PER_MINUTE
    }

    #[test]
    fn unit_constants_agree() {
        assert_eq!(MS_PER_MINUTE * 60, MS_PER_HOUR);
        assert_eq!(MS_PER_HOUR * 24, MS_PER_DAY);
    }

    #[test]
    fn rejects_reversed_range() {
        assert!(TimeRange::new(2_000, 1_000).is_none());
    }

    #[test]
    fn accepts_empty_range() {
        let range = TimeRange::new(1_000, 1_000).unwrap();
        assert_eq!(range.duration_ms(), 0);
        assert!(range.is_empty());
        assert!(!range.contains(1_000));
    }

    #[test]
    fn contains_start_but_not_end() {
        let range = TimeRange::new(1_000, 2_000).unwrap();
        assert!(!range.contains(999));
        assert!(range.contains(1_000));
        assert!(range.contains(1_999));
        assert!(!range.contains(2_000));
    }

    #[test]
    fn now_ms_reads_the_wall_clock() {
        // 2020-01-01T00:00Z, well before any clock this code runs on.
        assert!(now_ms() > 1_577_836_800_000);
    }

    #[test]
    fn days_from_civil_counts_from_the_epoch() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(1970, 1, 2), 1);
        assert_eq!(days_from_civil(1969, 12, 31), -1);
        assert_eq!(days_from_civil(2000, 3, 1), 11_017);
        assert_eq!(days_from_civil(2026, 10, 1), 20_727);
    }

    #[test]
    fn days_from_civil_handles_leap_days() {
        assert_eq!(
            days_from_civil(2024, 2, 28) + 1,
            days_from_civil(2024, 2, 29)
        );
        assert_eq!(
            days_from_civil(2024, 2, 29) + 1,
            days_from_civil(2024, 3, 1)
        );
        assert_eq!(
            days_from_civil(1900, 2, 28) + 1,
            days_from_civil(1900, 3, 1)
        );
        assert_eq!(
            days_from_civil(2000, 2, 28) + 1,
            days_from_civil(2000, 2, 29)
        );
    }

    #[test]
    fn local_day_uses_a_zero_offset() {
        let noon = days_from_civil(2026, 10, 15) * MS_PER_DAY + 12 * MS_PER_HOUR;
        let day = local_day_containing(noon, fixed(0));
        assert_eq!(day.start_ms, days_from_civil(2026, 10, 15) * MS_PER_DAY);
        assert_eq!(day.duration_ms(), MS_PER_DAY);
    }

    #[test]
    fn local_day_handles_a_negative_offset() {
        // 2026-10-15T02:00Z is 2026-10-14T21:00 at UTC-5.
        let day = local_day_containing(1_792_029_600_000, fixed(-300));
        assert_eq!(day.start_ms, 1_791_954_000_000);
        assert_eq!(day.end_ms, 1_791_954_000_000 + MS_PER_DAY);
    }

    #[test]
    fn local_day_handles_a_positive_offset_across_the_day_boundary() {
        // 2026-10-15T23:30Z is 2026-10-16T01:30 at UTC+2.
        let day = local_day_containing(1_792_107_000_000, fixed(120));
        assert_eq!(
            day.start_ms,
            days_from_civil(2026, 10, 16) * MS_PER_DAY - 2 * MS_PER_HOUR
        );
    }

    #[test]
    fn local_day_works_before_the_epoch() {
        let day = local_day_containing(-1, fixed(0));
        assert_eq!(day.start_ms, -MS_PER_DAY);
        assert_eq!(day.end_ms, 0);
    }

    #[test]
    fn local_day_of_text_starts_at_local_midnight() {
        let day = local_day_of_text("2026-10-01", fixed(-300)).unwrap();
        assert_eq!(day.start_ms, 1_790_830_800_000);
        assert_eq!(day.end_ms, 1_790_830_800_000 + MS_PER_DAY);
        let east = local_day_of_text("2026-10-01", fixed(120)).unwrap();
        assert_eq!(east.start_ms, 1_790_805_600_000);
    }

    #[test]
    fn local_day_of_text_rejects_invalid_dates() {
        assert_eq!(local_day_of_text("2026-02-29", fixed(0)), None);
        assert_eq!(local_day_of_text("2026-02-30", fixed(0)), None);
        assert_eq!(local_day_of_text("2026-13-01", fixed(0)), None);
        assert_eq!(local_day_of_text("2026-10-0x", fixed(0)), None);
        assert!(local_day_of_text("2024-02-29", fixed(0)).is_some());
    }

    #[test]
    fn dates_must_be_ten_ascii_characters_in_iso_form() {
        assert!(local_day_of_text("2026-1-20", fixed(0)).is_none());
        assert!(local_day_of_text("2026/10/20", fixed(0)).is_none());
        assert!(local_day_of_text("", fixed(0)).is_none());
    }

    #[test]
    fn fall_back_day_is_25_hours_and_starts_at_edt_midnight() {
        // 2026-11-01T15:00Z is 10:00 EST, on the day New York repeats an hour.
        let now_ms = 1_793_545_200_000;
        let day = local_day_containing(now_ms, new_york_2026);
        assert_eq!(day.start_ms, 1_793_505_600_000, "2026-11-01T04:00Z");
        assert_eq!(day.duration_ms(), 25 * MS_PER_HOUR);
    }

    #[test]
    fn spring_forward_day_is_23_hours_and_starts_at_est_midnight() {
        // 2026-03-08T15:00Z is 11:00 EDT, on the day New York skips an hour.
        let march_8 = days_from_civil(2026, 3, 8) * MS_PER_DAY;
        let day = local_day_containing(march_8 + 15 * MS_PER_HOUR, new_york_2026);
        assert_eq!(day.start_ms, march_8 + 5 * MS_PER_HOUR, "2026-03-08T05:00Z");
        assert_eq!(day.end_ms, march_8 + MS_PER_DAY + 4 * MS_PER_HOUR);
        assert_eq!(day.duration_ms(), 23 * MS_PER_HOUR);
    }

    #[test]
    fn a_fall_back_date_resolves_to_its_own_midnight() {
        let day = local_day_of_text("2026-11-01", new_york_2026).unwrap();
        assert_eq!(day.start_ms, 1_793_505_600_000, "2026-11-01T04:00Z");
        assert_eq!(day.end_ms, 1_793_595_600_000, "2026-11-02T05:00Z");
    }

    #[test]
    fn local_day_count_of_an_empty_range_is_zero() {
        assert_eq!(local_day_count(TimeRange::new(0, 0).unwrap(), fixed(0)), 0);
    }

    #[test]
    fn local_day_count_does_not_count_the_day_after_the_range() {
        let two_days = TimeRange::new(0, 2 * MS_PER_DAY).unwrap();
        assert_eq!(local_day_count(two_days, fixed(0)), 2);
        let partial = TimeRange::new(MS_PER_HOUR, MS_PER_HOUR + 1).unwrap();
        assert_eq!(local_day_count(partial, fixed(0)), 1);
    }

    #[test]
    fn local_day_buckets_start_at_local_midnights() {
        // At UTC+2, 1970-01-01T00:00Z is 02:00 local, so the range touches three dates.
        let range = TimeRange::new(0, 2 * MS_PER_DAY).unwrap();
        let buckets = local_day_buckets(range, fixed(120));
        assert_eq!(buckets.len(), 3);
        assert_eq!(buckets[0].start_ms, 0);
        assert_eq!(buckets[0].end_ms, MS_PER_DAY - 2 * MS_PER_HOUR);
        assert_eq!(buckets[1].end_ms, 2 * MS_PER_DAY - 2 * MS_PER_HOUR);
        assert_eq!(buckets[2].end_ms, range.end_ms);
    }

    #[test]
    fn local_day_buckets_start_at_the_range_start_and_end_at_its_end() {
        let range = TimeRange::new(12 * MS_PER_HOUR, 3 * MS_PER_DAY).unwrap();
        let buckets = local_day_buckets(range, fixed(0));
        assert_eq!(buckets.len(), 3);
        assert_eq!(buckets[0].start_ms, range.start_ms);
        assert_eq!(buckets[0].end_ms, MS_PER_DAY);
        assert_eq!(buckets[2].end_ms, range.end_ms);
    }

    #[test]
    fn a_fall_back_week_has_seven_buckets_with_a_25_hour_day() {
        let week = TimeRange::new(1_793_505_600_000, 1_794_114_000_000).unwrap();
        let buckets = local_day_buckets(week, new_york_2026);
        assert_eq!(local_day_count(week, new_york_2026), 7);
        assert_eq!(buckets.len(), 7);
        assert_eq!(buckets[0].duration_ms(), 25 * MS_PER_HOUR);
        for bucket in &buckets[1..] {
            assert_eq!(bucket.duration_ms(), MS_PER_DAY);
        }
        assert_eq!(buckets[6].end_ms, week.end_ms);
    }

    #[test]
    fn a_spring_forward_week_has_seven_buckets_with_a_23_hour_day() {
        let week = TimeRange::new(1_772_946_000_000, 1_773_547_200_000).unwrap();
        let buckets = local_day_buckets(week, new_york_2026);
        assert_eq!(local_day_count(week, new_york_2026), 7);
        assert_eq!(buckets.len(), 7);
        assert_eq!(buckets[0].start_ms, 1_772_946_000_000, "2026-03-08T05:00Z");
        assert_eq!(buckets[0].duration_ms(), 23 * MS_PER_HOUR);
        for bucket in &buckets[1..] {
            assert_eq!(bucket.duration_ms(), MS_PER_DAY);
        }
    }
}
