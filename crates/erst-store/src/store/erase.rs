//! Erasing a time range, and removing whole segments.
//!
//! A video segment cannot be cut, so erasing any part of a segment removes the
//! whole segment with every frame it holds. Text lines that no remaining frame
//! references go with their frames, and so do the spans the range covers.
//! Everything happens in one transaction. The writer then vacuums and truncates
//! the WAL so erased content does not survive in free pages, and the relative
//! paths it detached wait in `pending_unlinks` until the caller unlinks them.

use std::time::Duration;

use rusqlite::{Connection, OptionalExtension, params};

use crate::error::StoreError;
use crate::model::EraseOutcome;
use crate::schema;
use crate::store::{STAGE_SEGMENT_UNLINK, Store, frame_text};

/// A WAL checkpoint needs every reader to finish. Short attempts keep an erase
/// interactive, because the connection's five second lock timeout would
/// otherwise stall each try. A snapshot that outlives the attempts fails with
/// [`StoreError::CheckpointBusy`], and the caller purges again later.
const PURGE_ATTEMPTS: u32 = 3;
const PURGE_BUSY_TIMEOUT_MS: u64 = 100;
const PURGE_RETRY_DELAY_MS: u64 = 20;

const SELECT_SEGMENT_PATH: &str = "SELECT path FROM segments WHERE id = ?1";

const SELECT_PENDING_UNLINKS: &str = "SELECT path FROM pending_unlinks ORDER BY path";

const DELETE_PENDING_UNLINK: &str = "DELETE FROM pending_unlinks WHERE path = ?1";

/// Staging tables let one pass collect the frames to delete, the lines they
/// reference, and the segments to remove, so every later statement is an
/// indexed lookup instead of a rescan.
const RESET_STAGING: &str = "
    CREATE TEMP TABLE IF NOT EXISTS erased_frames (id INTEGER PRIMARY KEY);
    DELETE FROM erased_frames;
    CREATE TEMP TABLE IF NOT EXISTS erased_lines (id INTEGER PRIMARY KEY);
    DELETE FROM erased_lines;";

const RESET_ERASED_SEGMENTS: &str = "
    CREATE TEMP TABLE IF NOT EXISTS erased_segments (
        id INTEGER PRIMARY KEY,
        path TEXT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER
    );
    DELETE FROM erased_segments;";

const STAGE_OVERLAPPING_SEGMENTS: &str = "
    INSERT INTO erased_segments (id, path, started_at, ended_at)
    SELECT id, path, started_at, ended_at FROM segments
    WHERE started_at < ?2 AND (ended_at IS NULL OR ended_at > ?1)";

/// Every detached video is recorded in the same transaction that removes its
/// segment, so the path survives a crash before the caller unlinks the file.
const STAGE_PENDING_UNLINKS: &str = "
    INSERT OR IGNORE INTO pending_unlinks (path)
    SELECT path FROM erased_segments WHERE path IS NOT NULL";

const STAGE_SEGMENT_FRAMES: &str =
    "INSERT OR IGNORE INTO erased_frames (id) SELECT id FROM frames WHERE segment_id = ?1";

const STAGE_RANGE_FRAMES: &str = "
    INSERT OR IGNORE INTO erased_frames (id)
    SELECT id FROM frames
    WHERE segment_id IN (SELECT id FROM erased_segments)
       OR (captured_at >= ?1 AND captured_at < ?2)";

const DELETE_STAGED_FRAMES: &str = "DELETE FROM frames WHERE id IN (SELECT id FROM erased_frames)";

/// Only lines no remaining frame shows are dropped, so lines shared with frames
/// outside the erased range stay searchable. Runs are trimmed first, so a line
/// with a run left still has a frame.
const DELETE_ORPHANED_LINES: &str = "
    DELETE FROM text_lines
    WHERE id IN (SELECT id FROM erased_lines)
      AND NOT EXISTS (SELECT 1 FROM line_runs r WHERE r.line_id = text_lines.id)";

const DELETE_STAGED_SEGMENTS: &str =
    "DELETE FROM segments WHERE id IN (SELECT id FROM erased_segments)";

/// Spans fully inside the requested half-open range disappear.
const DELETE_SPANS_INSIDE: &str = "
    DELETE FROM spans
    WHERE started_at >= ?1 AND started_at < ?2 AND ended_at IS NOT NULL AND ended_at <= ?2";

/// A span that starts before the range and ends inside it is cut at the start.
const CLIP_SPANS_AT_START: &str = "
    UPDATE spans SET ended_at = ?1
    WHERE started_at < ?1 AND ended_at IS NOT NULL AND ended_at > ?1 AND ended_at <= ?2";

/// A span that starts inside the range and ends after it is cut at the end.
const CLIP_SPANS_AT_END: &str = "
    UPDATE spans SET started_at = ?2
    WHERE started_at >= ?1 AND started_at < ?2 AND (ended_at IS NULL OR ended_at > ?2)";

/// A span covering the whole range keeps its row as the tail after the range,
/// because that is the id the focus tracker holds and closes later. The part
/// before the range becomes a new closed row. Insert first: moving the original
/// would otherwise hide it from the copy.
const INSERT_SPAN_BEFORE_RANGE: &str = "
    INSERT INTO spans (app_id, window_title, url, started_at, ended_at)
    SELECT app_id, window_title, url, started_at, ?1 FROM spans
    WHERE started_at < ?1 AND (ended_at IS NULL OR ended_at > ?2)";

const MOVE_SPAN_AFTER_RANGE: &str = "
    UPDATE spans SET started_at = ?2
    WHERE started_at < ?1 AND (ended_at IS NULL OR ended_at > ?2)";

const TRUNCATE_WAL: &str = "PRAGMA wal_checkpoint(TRUNCATE)";

impl Store {
    /// Erases everything recorded in `[start_ms, end_ms)`.
    ///
    /// Every segment whose time range overlaps the range is removed whole, with
    /// all of its frames, because a video cannot be cut. Frames captured inside
    /// the range are removed even when their segment survives. Spans are
    /// deleted, clipped, or split along the requested range. The returned
    /// outcome reports the union of the requested range and the removed closed
    /// segments; an open removed segment has no recorded end, so it only
    /// extends the start. `purge_complete` reports whether the WAL truncation
    /// succeeded; the row removal and the pending unlinks are durable either
    /// way.
    pub fn erase_range(&self, start_ms: i64, end_ms: i64) -> Result<EraseOutcome, StoreError> {
        if start_ms >= end_ms {
            return Ok(EraseOutcome {
                frames_removed: 0,
                segment_paths: Vec::new(),
                erased_from_ms: start_ms,
                erased_to_ms: end_ms,
                purge_complete: true,
            });
        }
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            transaction.execute_batch(RESET_STAGING)?;
            transaction.execute_batch(RESET_ERASED_SEGMENTS)?;
            transaction
                .prepare_cached(STAGE_OVERLAPPING_SEGMENTS)?
                .execute(params![start_ms, end_ms])?;
            transaction.execute(STAGE_PENDING_UNLINKS, [])?;

            let segments = erased_segments(&transaction)?;
            transaction
                .prepare_cached(STAGE_RANGE_FRAMES)?
                .execute(params![start_ms, end_ms])?;
            let frames_removed = delete_staged_frames(&transaction)?;
            transaction.execute(DELETE_STAGED_SEGMENTS, [])?;
            erase_spans(&transaction, start_ms, end_ms)?;
            transaction.commit()?;
            let purge_complete = purge_deleted_pages(connection).is_ok();

            let mut erased_from_ms = start_ms;
            let mut erased_to_ms = end_ms;
            let mut segment_paths = Vec::new();
            for segment in segments {
                erased_from_ms = erased_from_ms.min(segment.started_at);
                if let Some(ended_at) = segment.ended_at {
                    erased_to_ms = erased_to_ms.max(ended_at);
                }
                segment_paths.extend(segment.path);
            }
            Ok(EraseOutcome {
                frames_removed,
                segment_paths,
                erased_from_ms,
                erased_to_ms,
                purge_complete,
            })
        })
    }

    /// Removes a segment with its frames and the text lines they leave
    /// orphaned, returning the relative video path when it had one.
    ///
    /// The caller unlinks the file; the database never touches the disk. The
    /// path is recorded in `pending_unlinks` first, so it survives a failed
    /// unlink. After the commit the writer vacuums and truncates the WAL; when
    /// a reader still holds a snapshot that purge fails with
    /// [`StoreError::CheckpointBusy`], and the rows and the queued path are
    /// already durable.
    pub fn delete_segment(&self, id: i64) -> Result<Option<String>, StoreError> {
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            let path: Option<Option<String>> = transaction
                .prepare_cached(SELECT_SEGMENT_PATH)?
                .query_row([id], |row| row.get(0))
                .optional()?;
            let Some(path) = path else {
                return Err(StoreError::NotFound {
                    what: "segment",
                    id,
                });
            };
            transaction.execute(STAGE_SEGMENT_UNLINK, [id])?;
            transaction.execute_batch(RESET_STAGING)?;
            transaction
                .prepare_cached(STAGE_SEGMENT_FRAMES)?
                .execute([id])?;
            delete_staged_frames(&transaction)?;
            transaction.execute("DELETE FROM segments WHERE id = ?1", [id])?;
            transaction.commit()?;
            purge_deleted_pages(connection)?;
            Ok(path)
        })
    }

    /// Relative video paths whose rows are already gone but whose files may
    /// still be on disk, sorted.
    ///
    /// The engine drains this list when it opens the database and after an
    /// erase, so an interrupted unlink is retried.
    pub fn pending_unlinks(&self) -> Result<Vec<String>, StoreError> {
        self.with_reader(|connection| {
            let mut statement = connection.prepare_cached(SELECT_PENDING_UNLINKS)?;
            let rows = statement.query_map([], |row| row.get(0))?;
            Ok(rows.collect::<Result<Vec<_>, _>>()?)
        })
    }

    /// Drops a path from the pending list after its file was unlinked.
    ///
    /// Dropping a path that is not listed is not an error, so a retried unlink
    /// is harmless.
    pub fn unlink_done(&self, path: &str) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            connection
                .prepare_cached(DELETE_PENDING_UNLINK)?
                .execute([path])?;
            Ok(())
        })
    }
}

/// A segment row staged for removal, before its row disappears.
struct ErasedSegment {
    path: Option<String>,
    started_at: i64,
    ended_at: Option<i64>,
}

fn erased_segments(connection: &Connection) -> Result<Vec<ErasedSegment>, StoreError> {
    let mut statement = connection.prepare_cached(
        "SELECT path, started_at, ended_at FROM erased_segments ORDER BY started_at ASC, id ASC",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(ErasedSegment {
            path: row.get(0)?,
            started_at: row.get(1)?,
            ended_at: row.get(2)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn delete_staged_frames(connection: &Connection) -> Result<u64, StoreError> {
    frame_text::stage_erased_lines(connection)?;
    let removed = connection.execute(DELETE_STAGED_FRAMES, [])?;
    frame_text::trim_runs(connection)?;
    connection.execute(DELETE_ORPHANED_LINES, [])?;
    Ok(u64::try_from(removed).unwrap_or(u64::MAX))
}

/// Applies the span rules in an order where each statement sees the original
/// rows it needs: the before piece is copied first, then the original row moves
/// to the end of the range, then every other rule edits in place.
fn erase_spans(connection: &Connection, start_ms: i64, end_ms: i64) -> Result<(), StoreError> {
    let parameters = params![start_ms, end_ms];
    connection.execute(INSERT_SPAN_BEFORE_RANGE, parameters)?;
    connection.execute(MOVE_SPAN_AFTER_RANGE, parameters)?;
    connection.execute(DELETE_SPANS_INSIDE, parameters)?;
    connection.execute(CLIP_SPANS_AT_START, parameters)?;
    connection.execute(CLIP_SPANS_AT_END, parameters)?;
    Ok(())
}

/// Frees the pages the erase left behind and truncates the WAL, so erased text
/// cannot be read back out of the files.
///
/// The busy timeout is lowered for the checkpoint only: with the connection's
/// usual five seconds, one busy checkpoint would stall the erase longer than
/// the whole retry loop.
fn purge_deleted_pages(connection: &Connection) -> Result<(), StoreError> {
    schema::release_free_pages(connection)?;
    connection.busy_timeout(Duration::from_millis(PURGE_BUSY_TIMEOUT_MS))?;
    let truncated = truncate_wal(connection);
    let restored = connection.busy_timeout(Duration::from_millis(schema::BUSY_TIMEOUT_MS));
    restored?;
    truncated
}

fn truncate_wal(connection: &Connection) -> Result<(), StoreError> {
    for attempt in 1..=PURGE_ATTEMPTS {
        let busy: i64 = connection.query_row(TRUNCATE_WAL, [], |row| row.get(0))?;
        if busy == 0 {
            return Ok(());
        }
        if attempt < PURGE_ATTEMPTS {
            std::thread::sleep(Duration::from_millis(PURGE_RETRY_DELAY_MS));
        }
    }
    Err(StoreError::CheckpointBusy)
}
