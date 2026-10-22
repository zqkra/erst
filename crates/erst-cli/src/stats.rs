//! `erst stats`: what the database holds and what it costs on disk.

use std::io::Write;

use anyhow::{Context, Result};
use erst_core::time::MS_PER_DAY;
use erst_store::{StorageStats, Store};
use serde::Serialize;

use crate::cli::StatsArgs;
use crate::format;

const LABEL_WIDTH: usize = 14;

/// Reads storage statistics and writes the requested format.
pub fn run(store: &Store, args: &StatsArgs, now_ms: i64, out: &mut impl Write) -> Result<()> {
    let stats = store
        .storage_stats(now_ms)
        .context("could not read storage statistics")?;
    if args.json {
        write_json(&stats, now_ms, out)
    } else {
        write_text(&stats, now_ms, out)
    }
}

/// Average stored bytes per day over the recorded span, at least one day.
#[allow(clippy::cast_precision_loss)] // display only: an average does not need 64 bits of precision
fn average_bytes_per_day(stats: &StorageStats, now_ms: i64) -> u64 {
    let Some(oldest_ms) = stats.oldest_ms else {
        return 0;
    };
    let newest_ms = stats.newest_ms.unwrap_or(now_ms);
    let span_ms = newest_ms.saturating_sub(oldest_ms).max(MS_PER_DAY);
    let total_bytes = stats.video_bytes.saturating_add(stats.database_bytes);
    let per_day = (total_bytes as f64) * (MS_PER_DAY as f64) / (span_ms as f64);
    if per_day.is_finite() && per_day >= 0.0 {
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        {
            per_day.round() as u64
        }
    } else {
        0
    }
}

#[derive(Debug, Serialize)]
struct JsonStats {
    database_bytes: u64,
    database: String,
    video_bytes: u64,
    video: String,
    video_last_24h_bytes: u64,
    video_last_24h: String,
    segment_count: u64,
    frame_count: u64,
    unique_line_count: u64,
    oldest_ms: Option<i64>,
    newest_ms: Option<i64>,
    oldest: Option<String>,
    newest: Option<String>,
    average_bytes_per_day: u64,
    average_per_day: String,
}

fn snapshot(stats: &StorageStats, now_ms: i64) -> JsonStats {
    let average = average_bytes_per_day(stats, now_ms);
    JsonStats {
        database_bytes: stats.database_bytes,
        database: format::human_bytes(stats.database_bytes),
        video_bytes: stats.video_bytes,
        video: format::human_bytes(stats.video_bytes),
        video_last_24h_bytes: stats.video_bytes_last_24h,
        video_last_24h: format::human_bytes(stats.video_bytes_last_24h),
        segment_count: stats.segment_count,
        frame_count: stats.frame_count,
        unique_line_count: stats.unique_line_count,
        oldest_ms: stats.oldest_ms,
        newest_ms: stats.newest_ms,
        oldest: stats.oldest_ms.map(format::local_stamp),
        newest: stats.newest_ms.map(format::local_stamp),
        average_bytes_per_day: average,
        average_per_day: format::human_bytes(average),
    }
}

fn write_json(stats: &StorageStats, now_ms: i64, out: &mut impl Write) -> Result<()> {
    serde_json::to_writer_pretty(&mut *out, &snapshot(stats, now_ms))?;
    writeln!(out)?;
    Ok(())
}

fn write_text(stats: &StorageStats, now_ms: i64, out: &mut impl Write) -> Result<()> {
    let view = snapshot(stats, now_ms);
    let rows = [
        ("Database", view.database),
        ("Video", view.video),
        ("Video (24h)", view.video_last_24h),
        ("Segments", format::grouped(stats.segment_count)),
        ("Frames", format::grouped(stats.frame_count)),
        ("Unique lines", format::grouped(stats.unique_line_count)),
        ("First", view.oldest.unwrap_or_else(|| String::from("-"))),
        ("Last", view.newest.unwrap_or_else(|| String::from("-"))),
        ("Average/day", view.average_per_day),
    ];
    for (label, value) in rows {
        writeln!(out, "{label:<LABEL_WIDTH$}{value}")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use erst_core::time::MS_PER_DAY;
    use erst_store::StorageStats;

    use super::average_bytes_per_day;

    fn stats(
        video_bytes: u64,
        database_bytes: u64,
        oldest_ms: Option<i64>,
        newest_ms: Option<i64>,
    ) -> StorageStats {
        StorageStats {
            video_bytes,
            database_bytes,
            segment_count: 1,
            frame_count: 1,
            unique_line_count: 1,
            oldest_ms,
            newest_ms,
            video_bytes_last_24h: 0,
        }
    }

    #[test]
    fn average_is_zero_without_frames() {
        assert_eq!(average_bytes_per_day(&stats(500, 500, None, None), 10), 0);
    }

    #[test]
    fn average_divides_by_days_of_recorded_span() {
        let per_day = 1_000_u64 * 1024;
        let stats = stats(4 * per_day, 0, Some(0), Some(4 * MS_PER_DAY));
        assert_eq!(average_bytes_per_day(&stats, 4 * MS_PER_DAY), per_day);
    }

    #[test]
    fn average_uses_one_day_for_a_short_span() {
        let stats = stats(100, 100, Some(0), Some(3_600_000));
        assert_eq!(average_bytes_per_day(&stats, 3_600_000), 200);
    }
}
