//! Reads. Every method takes the reader connection, so UI queries never wait on writes.

use std::collections::BTreeMap;

use rusqlite::{OptionalExtension, Params, Row, params};

use crate::error::StoreError;
use crate::model::{
    FrameDetail, FrameStamp, LineSource, ReminderRow, SegmentRow, SpanRow, StorageStats,
    TrackFrameRow,
};
use crate::store::{Store, frame_text, u64_from_sql};

const DAY_MS: i64 = 86_400_000;

const SELECT_FRAME_STAMP: &str = "
    SELECT id, captured_at, change_ratio FROM frames
    WHERE captured_at >= ?1 AND captured_at < ?2
    ORDER BY captured_at ASC, id ASC";

const SELECT_TRACK_FRAMES: &str = "
    SELECT f.id, f.captured_at, f.change_ratio, a.bundle_id, a.name, f.window_title, f.url
    FROM frames f
    LEFT JOIN apps a ON a.id = f.app_id
    WHERE f.captured_at >= ?1 AND f.captured_at < ?2
    ORDER BY f.captured_at, f.id";

const SELECT_NEAREST_BEFORE: &str = "
    SELECT id, captured_at, change_ratio FROM frames
    WHERE captured_at <= ?1
    ORDER BY captured_at DESC, id DESC
    LIMIT 1";

const SELECT_NEAREST_AFTER: &str = "
    SELECT id, captured_at, change_ratio FROM frames
    WHERE captured_at > ?1
    ORDER BY captured_at ASC, id ASC
    LIMIT 1";

const SELECT_FRAME_AT: &str = "SELECT captured_at FROM frames WHERE id = ?1";

const SELECT_NEIGHBORS_BEFORE: &str = "
    SELECT id, captured_at, change_ratio FROM frames
    WHERE captured_at < ?1 OR (captured_at = ?1 AND id < ?2)
    ORDER BY captured_at DESC, id DESC
    LIMIT ?3";

const SELECT_NEIGHBORS_AFTER: &str = "
    SELECT id, captured_at, change_ratio FROM frames
    WHERE captured_at > ?1 OR (captured_at = ?1 AND id > ?2)
    ORDER BY captured_at ASC, id ASC
    LIMIT ?3";

const SELECT_FRAME_DETAIL: &str = "
    SELECT f.id, f.captured_at, f.change_ratio,
           COALESCE(a.bundle_id, ''), COALESCE(a.name, ''),
           f.window_title, f.url, f.segment_id, s.path, s.started_at, f.pts_ms, s.tier
    FROM frames f
    LEFT JOIN apps a ON a.id = f.app_id
    JOIN segments s ON s.id = f.segment_id
    WHERE f.id = ?1";

const SELECT_CLOSED_SPANS: &str = "
    SELECT s.id, a.bundle_id, a.name, s.window_title, s.url, s.started_at, s.ended_at
    FROM spans s
    JOIN apps a ON a.id = s.app_id
    WHERE s.ended_at IS NOT NULL
      AND s.ended_at > ?1
      AND s.started_at < ?2";

const SELECT_OPEN_SPANS: &str = "
    SELECT s.id, a.bundle_id, a.name, s.window_title, s.url, s.started_at, s.ended_at
    FROM spans s
    JOIN apps a ON a.id = s.app_id
    WHERE s.ended_at IS NULL
      AND s.started_at < ?1";

pub(super) const SELECT_LAST_SPAN_BEFORE: &str = "
    SELECT s.id, a.bundle_id, a.name, s.window_title, s.url, s.started_at, s.ended_at
    FROM spans s
    JOIN apps a ON a.id = s.app_id
    WHERE a.bundle_id = ?1
      AND s.window_title IS ?2
      AND s.ended_at IS NOT NULL
      AND s.ended_at <= ?3
      AND s.started_at <= ?3
    ORDER BY s.started_at DESC
    LIMIT 1";

const SELECT_SEGMENTS: &str = "
    SELECT id, path, started_at, ended_at, width, height, bytes, tier
    FROM segments
    ORDER BY started_at DESC, id DESC";

const SELECT_OPEN_SEGMENT: &str = "
    SELECT id, path, started_at, ended_at, width, height, bytes, tier
    FROM segments
    WHERE ended_at IS NULL
    ORDER BY started_at DESC, id DESC
    LIMIT 1";

const SELECT_STORAGE_STATS: &str = "
    SELECT
      (SELECT COALESCE(SUM(bytes), 0) FROM segments),
      (SELECT COUNT(*) FROM segments),
      (SELECT COUNT(*) FROM frames),
      (SELECT COUNT(*) FROM text_lines),
      (SELECT MIN(captured_at) FROM frames),
      (SELECT MAX(captured_at) FROM frames),
      (SELECT COALESCE(SUM(bytes), 0) FROM segments WHERE started_at >= ?1)";

const SELECT_REMINDERS: &str = "
    SELECT id, frame_id, created_at, due_at, note, done_at FROM reminders
    ORDER BY due_at ASC, id ASC";

const SELECT_DUE_REMINDERS: &str = "
    SELECT id, frame_id, created_at, due_at, note, done_at FROM reminders
    WHERE done_at IS NULL AND due_at <= ?1
    ORDER BY due_at ASC, id ASC";

const SELECT_SETTINGS: &str = "SELECT key, value FROM settings ORDER BY key";

const SELECT_EXCLUDED_APPS: &str = "SELECT bundle_id FROM excluded_apps ORDER BY bundle_id";

fn read_stamp(row: &Row<'_>) -> rusqlite::Result<FrameStamp> {
    Ok(FrameStamp {
        id: row.get(0)?,
        captured_at: row.get(1)?,
        change_ratio: row.get(2)?,
    })
}

fn read_track_frame(row: &Row<'_>) -> rusqlite::Result<TrackFrameRow> {
    Ok(TrackFrameRow {
        id: row.get(0)?,
        captured_at: row.get(1)?,
        change_ratio: row.get(2)?,
        bundle_id: row.get(3)?,
        app_name: row.get(4)?,
        window_title: row.get(5)?,
        url: row.get(6)?,
    })
}

fn read_segment(row: &Row<'_>) -> rusqlite::Result<SegmentRow> {
    Ok(SegmentRow {
        id: row.get(0)?,
        path: row.get(1)?,
        started_at: row.get(2)?,
        ended_at: row.get(3)?,
        width: row.get(4)?,
        height: row.get(5)?,
        bytes: u64_from_sql(row.get(6)?),
        tier: row.get(7)?,
    })
}

fn read_reminder(row: &Row<'_>) -> rusqlite::Result<ReminderRow> {
    Ok(ReminderRow {
        id: row.get(0)?,
        frame_id: row.get(1)?,
        created_at: row.get(2)?,
        due_at: row.get(3)?,
        note: row.get(4)?,
        done_at: row.get(5)?,
    })
}

fn read_span(row: &Row<'_>) -> rusqlite::Result<SpanRow> {
    Ok(SpanRow {
        id: row.get(0)?,
        bundle_id: row.get(1)?,
        app_name: row.get(2)?,
        window_title: row.get(3)?,
        url: row.get(4)?,
        started_at: row.get(5)?,
        ended_at: row.get(6)?,
    })
}

/// Runs a query to completion. The statement binding lives here, so every list
/// read is one call instead of a statement scope repeated per method.
fn query_rows<T>(
    connection: &rusqlite::Connection,
    sql: &str,
    parameters: impl Params,
    map: impl FnMut(&Row<'_>) -> rusqlite::Result<T>,
) -> Result<Vec<T>, StoreError> {
    let mut statement = connection.prepare_cached(sql)?;
    let rows = statement.query_map(parameters, map)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

impl Store {
    /// Frames captured in `[start_ms, end_ms)`, oldest first.
    pub fn frames_in_range(
        &self,
        start_ms: i64,
        end_ms: i64,
    ) -> Result<Vec<FrameStamp>, StoreError> {
        self.with_reader(|connection| {
            query_rows(
                connection,
                SELECT_FRAME_STAMP,
                params![start_ms, end_ms],
                read_stamp,
            )
        })
    }

    /// Frames captured in `[start_ms, end_ms)`, oldest first, with their app,
    /// window title, URL, and change ratio.
    pub fn track_frames(
        &self,
        start_ms: i64,
        end_ms: i64,
    ) -> Result<Vec<TrackFrameRow>, StoreError> {
        self.with_reader(|connection| {
            query_rows(
                connection,
                SELECT_TRACK_FRAMES,
                params![start_ms, end_ms],
                read_track_frame,
            )
        })
    }

    /// The frame closest in time to `at_ms`, earlier on a tie.
    pub fn nearest_frame(&self, at_ms: i64) -> Result<Option<FrameStamp>, StoreError> {
        self.with_reader(|connection| {
            let earlier = connection
                .prepare_cached(SELECT_NEAREST_BEFORE)?
                .query_row([at_ms], read_stamp)
                .optional()?;
            let later = connection
                .prepare_cached(SELECT_NEAREST_AFTER)?
                .query_row([at_ms], read_stamp)
                .optional()?;
            Ok(match (earlier, later) {
                (Some(earlier), Some(later)) => {
                    let before_gap = at_ms.saturating_sub(earlier.captured_at);
                    let after_gap = later.captured_at.saturating_sub(at_ms);
                    Some(if after_gap < before_gap {
                        later
                    } else {
                        earlier
                    })
                }
                (earlier, later) => earlier.or(later),
            })
        })
    }

    /// Up to `before` frames earlier and `after` frames later than `frame_id`,
    /// returned in ascending time order.
    pub fn neighbors(
        &self,
        frame_id: i64,
        before: u32,
        after: u32,
    ) -> Result<Vec<FrameStamp>, StoreError> {
        self.with_reader(|connection| {
            let captured_at: Option<i64> = connection
                .prepare_cached(SELECT_FRAME_AT)?
                .query_row([frame_id], |row| row.get(0))
                .optional()?;
            let Some(captured_at) = captured_at else {
                return Err(StoreError::NotFound {
                    what: "frame",
                    id: frame_id,
                });
            };
            let mut stamps = query_rows(
                connection,
                SELECT_NEIGHBORS_BEFORE,
                params![captured_at, frame_id, i64::from(before)],
                read_stamp,
            )?;
            stamps.reverse();
            stamps.extend(query_rows(
                connection,
                SELECT_NEIGHBORS_AFTER,
                params![captured_at, frame_id, i64::from(after)],
                read_stamp,
            )?);
            Ok(stamps)
        })
    }

    /// The frame with its app, segment, and every stored line.
    pub fn frame_detail(&self, id: i64) -> Result<FrameDetail, StoreError> {
        self.with_reader(|connection| {
            let detail: Option<FrameDetail> = connection
                .prepare_cached(SELECT_FRAME_DETAIL)?
                .query_row([id], |row| {
                    Ok(FrameDetail {
                        stamp: FrameStamp {
                            id: row.get(0)?,
                            captured_at: row.get(1)?,
                            change_ratio: row.get(2)?,
                        },
                        bundle_id: row.get(3)?,
                        app_name: row.get(4)?,
                        window_title: row.get(5)?,
                        url: row.get(6)?,
                        segment_id: row.get(7)?,
                        segment_path: row.get(8)?,
                        segment_started_at: row.get(9)?,
                        pts_ms: row.get(10)?,
                        tier: row.get(11)?,
                        lines: Vec::new(),
                    })
                })
                .optional()?;
            let Some(mut detail) = detail else {
                return Err(StoreError::NotFound { what: "frame", id });
            };
            // A moment's text is what the frame showed, so the title line is left
            // out: the moment already names its window from `frames.window_title`.
            let placements: Vec<_> = frame_text::layout_of(connection, id)?
                .into_iter()
                .filter(|placement| placement.source != LineSource::Title)
                .collect();
            let texts = frame_text::texts(
                connection,
                placements.iter().map(|placement| placement.line_id),
            )?;
            detail.lines = frame_text::line_boxes(&placements, &texts);
            Ok(detail)
        })
    }

    /// Spans overlapping `[start_ms, end_ms)`, including open spans, oldest first.
    ///
    /// Closed and open spans are read separately so the closed part can seek
    /// `spans(ended_at, started_at)` by end time, while open spans use
    /// `spans(started_at)` until that index exists. The merged list is sorted
    /// here because a single SQL order would make the planner walk every span
    /// that started before `end_ms`.
    pub fn spans_in_range(&self, start_ms: i64, end_ms: i64) -> Result<Vec<SpanRow>, StoreError> {
        self.with_reader(|connection| {
            let mut spans = query_rows(
                connection,
                SELECT_CLOSED_SPANS,
                params![start_ms, end_ms],
                read_span,
            )?;
            spans.extend(query_rows(
                connection,
                SELECT_OPEN_SPANS,
                [end_ms],
                read_span,
            )?);
            spans.sort_by_key(|span| (span.started_at, span.id));
            Ok(spans)
        })
    }

    /// The most recent closed span of one app and window that ended at or
    /// before `before_ms`, or `None` when there is no earlier visit.
    ///
    /// Reads `spans(app_id, started_at)` backwards, so it is one index seek
    /// plus the window title check instead of a scan over all history.
    pub fn last_span_before(
        &self,
        bundle_id: &str,
        window_title: Option<&str>,
        before_ms: i64,
    ) -> Result<Option<SpanRow>, StoreError> {
        self.with_reader(|connection| {
            let span = connection
                .prepare_cached(SELECT_LAST_SPAN_BEFORE)?
                .query_row(params![bundle_id, window_title, before_ms], read_span)
                .optional()?;
            Ok(span)
        })
    }

    /// Every segment, newest first.
    pub fn segments(&self) -> Result<Vec<SegmentRow>, StoreError> {
        self.with_reader(|connection| {
            query_rows(connection, SELECT_SEGMENTS, params![], read_segment)
        })
    }

    /// The segment still being written, if one was left open.
    pub fn open_segment(&self) -> Result<Option<SegmentRow>, StoreError> {
        self.with_reader(|connection| {
            let segment = connection
                .prepare_cached(SELECT_OPEN_SEGMENT)?
                .query_row([], read_segment)
                .optional()?;
            Ok(segment)
        })
    }

    /// Aggregate storage facts as of `now_ms`.
    ///
    /// `database_bytes` is the page count times the page size of the main
    /// database file, as SQLite reports it.
    pub fn storage_stats(&self, now_ms: i64) -> Result<StorageStats, StoreError> {
        self.with_reader(|connection| {
            let page_bytes: i64 = {
                let page_count: i64 =
                    connection.pragma_query_value(None, "page_count", |row| row.get(0))?;
                let page_size: i64 =
                    connection.pragma_query_value(None, "page_size", |row| row.get(0))?;
                page_count.saturating_mul(page_size)
            };
            let cutoff_ms = now_ms.saturating_sub(DAY_MS);
            let stats =
                connection
                    .prepare_cached(SELECT_STORAGE_STATS)?
                    .query_row([cutoff_ms], |row| {
                        Ok(StorageStats {
                            video_bytes: u64_from_sql(row.get(0)?),
                            database_bytes: u64_from_sql(page_bytes),
                            segment_count: u64_from_sql(row.get(1)?),
                            frame_count: u64_from_sql(row.get(2)?),
                            unique_line_count: u64_from_sql(row.get(3)?),
                            oldest_ms: row.get(4)?,
                            newest_ms: row.get(5)?,
                            video_bytes_last_24h: u64_from_sql(row.get(6)?),
                        })
                    })?;
            Ok(stats)
        })
    }

    /// Open reminders due at or before `now_ms`, soonest first.
    pub fn due_reminders(&self, now_ms: i64) -> Result<Vec<ReminderRow>, StoreError> {
        self.with_reader(|connection| {
            query_rows(connection, SELECT_DUE_REMINDERS, [now_ms], read_reminder)
        })
    }

    /// Every reminder, by due time then id.
    pub fn reminders(&self) -> Result<Vec<ReminderRow>, StoreError> {
        self.with_reader(|connection| {
            query_rows(connection, SELECT_REMINDERS, params![], read_reminder)
        })
    }

    /// All settings.
    pub fn settings(&self) -> Result<BTreeMap<String, String>, StoreError> {
        self.with_reader(|connection| {
            let pairs = query_rows(connection, SELECT_SETTINGS, params![], |row| {
                Ok((row.get(0)?, row.get(1)?))
            })?;
            Ok(pairs.into_iter().collect())
        })
    }

    /// Excluded bundle ids, sorted.
    pub fn excluded_apps(&self) -> Result<Vec<String>, StoreError> {
        self.with_reader(|connection| {
            query_rows(connection, SELECT_EXCLUDED_APPS, params![], |row| {
                row.get(0)
            })
        })
    }
}
