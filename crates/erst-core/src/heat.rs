//! Heat levels for kept frames: evenly spaced buckets for a strip, and
//! wall-clock hours of local days for a month.

use crate::error::CoreError;
use crate::time::{MAX_BUCKETS, MS_PER_DAY, MS_PER_HOUR, TimeRange, local_day_buckets};

/// Hours in one day of [`hourly_heat`].
pub const HOURS_PER_DAY: usize = 24;

/// A change ratio this large or larger counts as a fully active stamp.
const FULL_CHANGE_RATIO: f32 = 0.05;

/// Maps per stamp change ratios to intensity `0..=5` buckets over `range`.
///
/// Each bucket sums `min(1.0, change_ratio * 20.0)` over the stamps inside it.
/// A bucket with no stamp is `0`. Other buckets scale against the busiest
/// bucket: `clamp(1 + floor(intensity * 4 / max_intensity), 1, 5)`. Stamps
/// outside the half-open range are ignored and may arrive unsorted. A stamped
/// bucket whose stamps carry no intensity still gets level 1. Returns an empty
/// vector when `buckets` is zero or the range is empty.
///
/// # Errors
///
/// Returns [`CoreError::TooManyBuckets`] when `buckets` is above [`MAX_BUCKETS`].
pub fn heat_buckets(
    stamps: &[(i64, f32)],
    range: TimeRange,
    buckets: usize,
) -> Result<Vec<u8>, CoreError> {
    if buckets > MAX_BUCKETS {
        return Err(CoreError::TooManyBuckets {
            count: u64::try_from(buckets).unwrap_or(u64::MAX),
        });
    }
    let duration = range.duration_ms();
    let Some(duration) = u128::try_from(duration).ok().filter(|value| *value > 0) else {
        return Ok(Vec::new());
    };
    if buckets == 0 {
        return Ok(Vec::new());
    }
    let bucket_count = u128::try_from(buckets).unwrap_or(u128::MAX);
    let mut slots = Slots::new(buckets);
    for &(stamp_ms, change_ratio) in stamps {
        if !range.contains(stamp_ms) {
            continue;
        }
        let offset = u128::try_from(stamp_ms.saturating_sub(range.start_ms)).unwrap_or(0);
        if let Ok(index) = usize::try_from(offset.saturating_mul(bucket_count) / duration) {
            slots.add(index, change_ratio);
        }
    }
    Ok(slots.levels())
}

/// One local day of [`hourly_heat`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DayHeat {
    /// The day, from its local midnight to the next: 23 or 25 hours on a
    /// daylight saving day, and cut short where the range ends.
    pub day: TimeRange,
    /// A level `0..=5` for each wall-clock hour, midnight first.
    pub hours: [u8; HOURS_PER_DAY],
}

/// Heat for every wall-clock hour of the local days `range` touches.
///
/// The first day starts at `range.start_ms`, so a range that starts at a
/// local midnight gives whole days. A stamp counts toward the hour its local
/// wall clock read: the repeated hour of a fall-back day folds into one slot,
/// and the hour a spring-forward day skips stays empty. Contributions and
/// levels follow [`heat_buckets`], scaled against the busiest hour of the
/// whole range so that days compare. Stamps outside the range are ignored.
///
/// # Errors
///
/// Returns [`CoreError::TooManyBuckets`] when the days hold more than
/// [`MAX_BUCKETS`] hours.
pub fn hourly_heat(
    stamps: &[(i64, f32)],
    range: TimeRange,
    offset_ms_at: impl Fn(i64) -> i64,
) -> Result<Vec<DayHeat>, CoreError> {
    let days = local_day_buckets(range, &offset_ms_at);
    let slot_count = days.len().saturating_mul(HOURS_PER_DAY);
    if slot_count > MAX_BUCKETS {
        return Err(CoreError::TooManyBuckets {
            count: u64::try_from(slot_count).unwrap_or(u64::MAX),
        });
    }
    let mut slots = Slots::new(slot_count);
    for &(stamp_ms, change_ratio) in stamps {
        if !range.contains(stamp_ms) {
            continue;
        }
        let day = days.partition_point(|day| day.end_ms <= stamp_ms);
        let wall_ms = stamp_ms.saturating_add(offset_ms_at(stamp_ms));
        let hour = usize::try_from(wall_ms.rem_euclid(MS_PER_DAY) / MS_PER_HOUR).unwrap_or(0);
        slots.add(day * HOURS_PER_DAY + hour, change_ratio);
    }
    let levels = slots.levels();
    let (rows, _) = levels.as_chunks::<HOURS_PER_DAY>();
    Ok(days
        .iter()
        .zip(rows)
        .map(|(day, hours)| DayHeat {
            day: *day,
            hours: *hours,
        })
        .collect())
}

/// Summed intensity per bucket, and whether any stamp landed in it.
struct Slots {
    intensity: Vec<f32>,
    stamped: Vec<bool>,
}

impl Slots {
    fn new(count: usize) -> Self {
        Self {
            intensity: vec![0.0; count],
            stamped: vec![false; count],
        }
    }

    /// Adds one stamp: `min(1.0, change_ratio * 20.0)`, nothing for a
    /// negative or non-finite ratio. An index past the end is ignored.
    fn add(&mut self, index: usize, change_ratio: f32) {
        let (Some(sum), Some(stamped)) =
            (self.intensity.get_mut(index), self.stamped.get_mut(index))
        else {
            return;
        };
        if change_ratio.is_finite() {
            *sum += (change_ratio / FULL_CHANGE_RATIO).clamp(0.0, 1.0);
        }
        *stamped = true;
    }

    /// `0` for an empty bucket, else `clamp(1 + floor(sum * 4 / max), 1, 5)`.
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)] // levels are clamped
    fn levels(&self) -> Vec<u8> {
        let max = self.intensity.iter().copied().fold(0.0_f32, f32::max);
        self.intensity
            .iter()
            .zip(&self.stamped)
            .map(|(&sum, &stamped)| {
                if !stamped {
                    0
                } else if max <= 0.0 {
                    1
                } else {
                    (1.0 + (sum * 4.0 / max).floor()).clamp(1.0, 5.0) as u8
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

    use super::{DayHeat, HOURS_PER_DAY, heat_buckets, hourly_heat};
    use crate::error::CoreError;
    use crate::time::{
        MAX_BUCKETS, MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE, TimeRange, days_from_civil,
        new_york_2026,
    };

    fn range(start_ms: i64, end_ms: i64) -> TimeRange {
        TimeRange::new(start_ms, end_ms).unwrap()
    }

    fn heat(stamps: &[(i64, f32)], range: TimeRange, buckets: usize) -> Vec<u8> {
        heat_buckets(stamps, range, buckets).unwrap()
    }

    #[test]
    fn empty_range_has_no_buckets() {
        assert!(heat(&[(0, 0.5)], range(10, 10), 5).is_empty());
        assert!(
            heat(
                &[],
                TimeRange {
                    start_ms: 10,
                    end_ms: 0
                },
                5
            )
            .is_empty()
        );
    }

    #[test]
    fn zero_buckets_returns_nothing() {
        assert!(heat(&[(0, 0.5)], range(0, 100), 0).is_empty());
    }

    #[test]
    fn no_stamps_are_all_zero() {
        assert_eq!(heat(&[], range(0, 1_000), 4), vec![0, 0, 0, 0]);
    }

    #[test]
    fn a_single_stamp_makes_its_bucket_the_hottest() {
        assert_eq!(heat(&[(50, 0.5)], range(0, 1_000), 4), vec![5, 0, 0, 0]);
    }

    #[test]
    fn equal_intensities_reach_level_five() {
        let stamps = [(0, 0.05), (400, 1.0)];
        assert_eq!(heat(&stamps, range(0, 800), 2), vec![5, 5]);
    }

    #[test]
    fn levels_scale_against_the_busiest_bucket() {
        let stamps = [(0, 1.0), (400, 0.0125)];
        assert_eq!(heat(&stamps, range(0, 800), 2), vec![5, 2]);
    }

    #[test]
    fn unsorted_stamps_are_grouped_correctly() {
        let sorted = heat(&[(10, 0.1), (30, 0.1), (90, 0.2)], range(0, 100), 2);
        let shuffled = heat(&[(90, 0.2), (10, 0.1), (30, 0.1)], range(0, 100), 2);
        assert_eq!(sorted, shuffled);
        assert_eq!(sorted, vec![5, 3]);
    }

    #[test]
    fn stamps_outside_the_half_open_range_are_ignored() {
        let stamps = [(-1, 1.0), (100, 1.0), (0, 0.5)];
        assert_eq!(heat(&stamps, range(0, 100), 2), vec![5, 0]);
    }

    #[test]
    fn bucket_edges_land_in_the_right_bucket() {
        assert_eq!(
            heat(&[(0, 1.0)], range(0, 100), 10),
            vec![5, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        );
        assert_eq!(
            heat(&[(99, 1.0)], range(0, 100), 10),
            vec![0, 0, 0, 0, 0, 0, 0, 0, 0, 5]
        );
        assert_eq!(
            heat(&[(10, 1.0)], range(0, 100), 10),
            vec![0, 5, 0, 0, 0, 0, 0, 0, 0, 0]
        );
    }

    #[test]
    fn each_stamp_contribution_is_capped_at_one() {
        let stamps = [(0, 0.5), (50, 0.05)];
        assert_eq!(heat(&stamps, range(0, 100), 2), vec![5, 5]);
    }

    #[test]
    fn a_zero_change_stamp_still_marks_its_bucket() {
        assert_eq!(heat(&[(0, 0.0)], range(0, 100), 2), vec![1, 0]);
    }

    #[test]
    fn non_finite_ratios_are_ignored() {
        let stamps = [(0, f32::NAN), (1, f32::INFINITY), (50, 0.5)];
        assert_eq!(heat(&stamps, range(0, 100), 2), vec![1, 5]);
    }

    #[test]
    fn negative_ratios_are_clamped_to_zero() {
        assert_eq!(heat(&[(0, -3.0), (50, 0.5)], range(0, 100), 2), vec![1, 5]);
    }

    #[test]
    fn more_buckets_than_stamps_stays_aligned() {
        assert_eq!(
            heat(&[(0, 1.0), (90, 0.5)], range(0, 100), 5),
            vec![5, 0, 0, 0, 5]
        );
    }
    #[test]
    fn bucket_counts_above_the_limit_are_rejected() {
        let error = heat_buckets(&[], range(0, 100), MAX_BUCKETS + 1).unwrap_err();
        assert_eq!(error, CoreError::TooManyBuckets { count: 4_097 });
    }

    #[test]
    fn the_bucket_limit_itself_is_allowed() {
        assert_eq!(heat(&[], range(0, 100_000), MAX_BUCKETS).len(), MAX_BUCKETS);
    }

    fn utc(_: i64) -> i64 {
        0
    }

    fn hourly(stamps: &[(i64, f32)], range: TimeRange) -> Vec<DayHeat> {
        hourly_heat(stamps, range, utc).unwrap()
    }

    fn hour_ms(day: i64, hour: i64) -> i64 {
        day * MS_PER_DAY + hour * MS_PER_HOUR
    }

    fn only(hour: usize, level: u8) -> [u8; HOURS_PER_DAY] {
        let mut hours = [0; HOURS_PER_DAY];
        hours[hour] = level;
        hours
    }

    #[test]
    fn an_empty_range_has_no_days() {
        assert!(hourly(&[(0, 1.0)], range(0, 0)).is_empty());
    }

    #[test]
    fn every_touched_day_gets_a_row_even_without_stamps() {
        let days = hourly(&[], range(0, 3 * MS_PER_DAY));
        assert_eq!(days.len(), 3);
        assert!(days.iter().all(|day| day.hours == [0; HOURS_PER_DAY]));
        assert_eq!(days[2].day, range(2 * MS_PER_DAY, 3 * MS_PER_DAY));
    }

    #[test]
    fn stamps_land_in_their_day_and_wall_clock_hour() {
        let stamps = [
            (hour_ms(0, 9) + 5, 1.0),
            (hour_ms(1, 23) + MS_PER_HOUR - 1, 1.0),
        ];
        let days = hourly(&stamps, range(0, 2 * MS_PER_DAY));
        assert_eq!(days[0].hours, only(9, 5));
        assert_eq!(days[1].hours, only(23, 5));
    }

    #[test]
    fn levels_compare_across_days_against_the_busiest_hour() {
        let busy: Vec<(i64, f32)> = (0..4)
            .map(|minute| (hour_ms(0, 10) + minute, 1.0))
            .collect();
        let stamps = [busy.as_slice(), &[(hour_ms(1, 10), 1.0)]].concat();
        let days = hourly(&stamps, range(0, 2 * MS_PER_DAY));
        assert_eq!(days[0].hours, only(10, 5));
        assert_eq!(days[1].hours, only(10, 2));
    }

    #[test]
    fn stamps_outside_the_range_are_ignored() {
        let stamps = [(-1, 1.0), (MS_PER_DAY, 1.0), (hour_ms(0, 3), 0.5)];
        assert_eq!(hourly(&stamps, range(0, MS_PER_DAY))[0].hours, only(3, 5));
    }

    #[test]
    fn a_range_cut_short_keeps_the_hours_on_the_wall_clock() {
        let start = hour_ms(0, 12);
        let days = hourly(&[(hour_ms(0, 15), 1.0)], range(start, MS_PER_DAY + start));
        assert_eq!(days.len(), 2);
        assert_eq!(days[0].day, range(start, MS_PER_DAY));
        assert_eq!(days[0].hours, only(15, 5));
    }

    #[test]
    fn local_hours_follow_the_zone_offset() {
        let day = days_from_civil(2026, 7, 1);
        let midnight = day * MS_PER_DAY + 4 * MS_PER_HOUR;
        let stamps = [(midnight + 9 * MS_PER_HOUR, 1.0)];
        let days = hourly_heat(
            &stamps,
            range(midnight, midnight + MS_PER_DAY),
            new_york_2026,
        )
        .unwrap();
        assert_eq!(days.len(), 1);
        assert_eq!(days[0].hours, only(9, 5));
    }

    #[test]
    fn the_repeated_hour_of_a_fall_back_day_folds_into_one_slot() {
        let midnight = days_from_civil(2026, 11, 1) * MS_PER_DAY + 4 * MS_PER_HOUR;
        let next_midnight = midnight + 25 * MS_PER_HOUR;
        let first_one_thirty = midnight + MS_PER_HOUR + 30 * MS_PER_MINUTE;
        let second_one_thirty = first_one_thirty + MS_PER_HOUR;
        let stamps = [
            (first_one_thirty, 1.0),
            (second_one_thirty, 1.0),
            (midnight + 12 * MS_PER_HOUR, 1.0),
        ];
        let days = hourly_heat(&stamps, range(midnight, next_midnight), new_york_2026).unwrap();
        assert_eq!(days.len(), 1);
        assert_eq!(days[0].day.duration_ms(), 25 * MS_PER_HOUR);
        assert_eq!(days[0].hours[1], 5);
        assert_eq!(days[0].hours[11], 3);
    }

    #[test]
    fn the_skipped_hour_of_a_spring_forward_day_stays_empty() {
        let midnight = days_from_civil(2026, 3, 8) * MS_PER_DAY + 5 * MS_PER_HOUR;
        let next_midnight = midnight + 23 * MS_PER_HOUR;
        let stamps: Vec<(i64, f32)> = (0..23)
            .map(|hour| (midnight + hour * MS_PER_HOUR, 1.0))
            .collect();
        let days = hourly_heat(&stamps, range(midnight, next_midnight), new_york_2026).unwrap();
        assert_eq!(days.len(), 1);
        assert_eq!(days[0].hours[2], 0);
        let mut expected = [5; HOURS_PER_DAY];
        expected[2] = 0;
        assert_eq!(days[0].hours, expected);
    }

    #[test]
    fn day_counts_whose_hours_pass_the_limit_are_rejected() {
        let day_limit = i64::try_from(MAX_BUCKETS / HOURS_PER_DAY).unwrap();
        assert_eq!(
            hourly(&[], range(0, day_limit * MS_PER_DAY)).len(),
            MAX_BUCKETS / HOURS_PER_DAY
        );
        let error = hourly_heat(&[], range(0, (day_limit + 1) * MS_PER_DAY), utc).unwrap_err();
        assert_eq!(error, CoreError::TooManyBuckets { count: 4_104 });
    }
}
