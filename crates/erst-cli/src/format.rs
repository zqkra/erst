//! Local time, sizes, and durations as people read them.

use chrono::{DateTime, Local, Offset, Utc};

/// Bytes in one kibibyte, used for every displayed size.
const BYTE_STEP: f64 = 1024.0;
const BYTE_UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
const SECONDS_PER_MINUTE: i64 = 60;
const MINUTES_PER_HOUR: i64 = 60;
const MS_PER_SECOND: i64 = 1_000;

fn local_datetime(at_ms: i64) -> Option<DateTime<Local>> {
    DateTime::<Utc>::from_timestamp_millis(at_ms).map(|utc| utc.with_timezone(&Local))
}

/// The local UTC offset at `at_ms` in milliseconds, positive east of Greenwich.
///
/// `erst_core` takes this function when it works out local days, so a day
/// starts at the right instant even across a daylight saving change.
pub fn utc_offset_ms(at_ms: i64) -> i64 {
    local_datetime(at_ms).map_or(0, |datetime| {
        i64::from(datetime.offset().fix().local_minus_utc()) * MS_PER_SECOND
    })
}

/// `at_ms` as local ISO 8601 with the offset, for example `2026-10-20T09:14:02-07:00`.
pub fn iso_local(at_ms: i64) -> String {
    local_datetime(at_ms).map_or_else(
        || format!("{at_ms}"),
        |datetime| datetime.format("%Y-%m-%dT%H:%M:%S%:z").to_string(),
    )
}

/// `at_ms` in a fixed offset, for tests and for text that must not depend on the machine.
#[cfg(test)]
pub fn iso_with_offset(at_ms: i64, offset_minutes: i32) -> Option<String> {
    let offset = chrono::FixedOffset::east_opt(offset_minutes.checked_mul(60)?)?;
    let utc = DateTime::<Utc>::from_timestamp_millis(at_ms)?;
    Some(
        utc.with_timezone(&offset)
            .format("%Y-%m-%dT%H:%M:%S%:z")
            .to_string(),
    )
}

/// Local clock time, for example `09:14:02`.
pub fn local_time(at_ms: i64) -> String {
    local_datetime(at_ms).map_or_else(
        || format!("{at_ms}"),
        |datetime| datetime.format("%H:%M:%S").to_string(),
    )
}

/// Local date and time without seconds, for summaries: `2026-10-20 09:14`.
pub fn local_stamp(at_ms: i64) -> String {
    local_datetime(at_ms).map_or_else(
        || format!("{at_ms}"),
        |datetime| datetime.format("%Y-%m-%d %H:%M").to_string(),
    )
}

/// Local civil date, for example `2026-10-20`.
pub fn local_date(at_ms: i64) -> Option<String> {
    local_datetime(at_ms).map(|datetime| datetime.format("%Y-%m-%d").to_string())
}

/// Pads `value` on the right with spaces to `width` characters.
pub fn pad_right(value: &str, width: usize) -> String {
    let mut padded = value.to_owned();
    padded.extend(std::iter::repeat_n(
        ' ',
        width.saturating_sub(value.chars().count()),
    ));
    padded
}

/// A byte count with one decimal from KB up: `12.4 MB`, `1.0 GB`, `840 KB`.
#[allow(clippy::cast_precision_loss)] // display only: bytes above 2^53 lose precision far beyond any disk
pub fn human_bytes(bytes: u64) -> String {
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= BYTE_STEP && unit + 1 < BYTE_UNITS.len() {
        value /= BYTE_STEP;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", BYTE_UNITS[unit])
    }
}

/// A duration at the coarsest useful precision: `2h 14m`, `41m`, `9s`.
pub fn human_duration(ms: i64) -> String {
    if ms <= 0 {
        return "0m".to_owned();
    }
    let total_seconds = ms / MS_PER_SECOND;
    if total_seconds < SECONDS_PER_MINUTE {
        return format!("{total_seconds}s");
    }
    let total_minutes = total_seconds / SECONDS_PER_MINUTE;
    if total_minutes < MINUTES_PER_HOUR {
        return format!("{total_minutes}m");
    }
    let hours = total_minutes / MINUTES_PER_HOUR;
    let minutes = total_minutes % MINUTES_PER_HOUR;
    if minutes == 0 {
        format!("{hours}h")
    } else {
        format!("{hours}h {minutes}m")
    }
}

/// A count with thin thousands separators: `812,004`.
pub fn grouped(value: u64) -> String {
    let digits = value.to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3);
    for (index, character) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            out.push(',');
        }
        out.push(character);
    }
    out
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use super::{grouped, human_bytes, human_duration, iso_with_offset};

    #[test]
    fn sizes_use_one_decimal_from_kilobytes() {
        assert_eq!(human_bytes(0), "0 B");
        assert_eq!(human_bytes(999), "999 B");
        assert_eq!(human_bytes(1024), "1.0 KB");
        assert_eq!(human_bytes(1536), "1.5 KB");
        assert_eq!(human_bytes(5 * 1024 * 1024), "5.0 MB");
        assert_eq!(human_bytes(3 * 1024 * 1024 * 1024), "3.0 GB");
    }

    #[test]
    fn durations_drop_empty_parts() {
        assert_eq!(human_duration(-5), "0m");
        assert_eq!(human_duration(0), "0m");
        assert_eq!(human_duration(9_000), "9s");
        assert_eq!(human_duration(41 * 60_000), "41m");
        assert_eq!(human_duration(2 * 3_600_000), "2h");
        assert_eq!(human_duration(2 * 3_600_000 + 14 * 60_000), "2h 14m");
    }

    #[test]
    fn counts_are_grouped_by_threes() {
        assert_eq!(grouped(0), "0");
        assert_eq!(grouped(999), "999");
        assert_eq!(grouped(1_000), "1,000");
        assert_eq!(grouped(812_004), "812,004");
        assert_eq!(grouped(1_234_567), "1,234,567");
    }

    #[test]
    fn iso_timestamps_carry_the_offset() {
        let instant = 1_792_029_600_000;
        assert_eq!(
            iso_with_offset(instant, 0).as_deref(),
            Some("2026-10-15T02:00:00+00:00")
        );
        assert_eq!(
            iso_with_offset(instant, -300).as_deref(),
            Some("2026-10-14T21:00:00-05:00")
        );
        assert_eq!(
            iso_with_offset(instant, 120).as_deref(),
            Some("2026-10-15T04:00:00+02:00")
        );
        assert_eq!(
            iso_with_offset(0, 0).as_deref(),
            Some("1970-01-01T00:00:00+00:00")
        );
    }
}
