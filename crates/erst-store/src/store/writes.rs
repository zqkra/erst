//! Writes. Every method takes the writer connection and commits before returning.

use rusqlite::{Connection, OptionalExtension, params};

use crate::error::StoreError;
use crate::model::{LineSource, NewFrame, NewLine};
use crate::normalize::normalize_text;
use crate::store::lines::insert_frame_lines;
use crate::store::{STAGE_SEGMENT_UNLINK, Store, u64_to_sql};

const TIER_REDUCED: u8 = 1;
const TIER_TEXT_ONLY: u8 = 2;

const UPSERT_APP: &str = "
    INSERT INTO apps (bundle_id, name) VALUES (?1, ?2)
    ON CONFLICT(bundle_id) DO UPDATE SET name = excluded.name
    WHERE apps.name <> excluded.name";

const SELECT_APP_ID: &str = "SELECT id FROM apps WHERE bundle_id = ?1";

const INSERT_FRAME: &str = "
    INSERT INTO frames (captured_at, segment_id, pts_ms, app_id, window_title, url, change_ratio)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)";

const INSERT_SEGMENT: &str = "
    INSERT INTO segments (path, started_at, width, height)
    VALUES (?1, ?2, ?3, ?4)";

const FINISH_SEGMENT: &str = "UPDATE segments SET ended_at = ?2, bytes = ?3 WHERE id = ?1";

const SELECT_UNFINISHED_SEGMENTS: &str = "
    SELECT s.id, s.path,
           COALESCE((SELECT MAX(f.captured_at) FROM frames f WHERE f.segment_id = s.id), s.started_at)
    FROM segments s
    WHERE s.ended_at IS NULL";

const INSERT_SPAN: &str = "
    INSERT INTO spans (app_id, window_title, url, started_at)
    VALUES (?1, ?2, ?3, ?4)";

const END_SPAN: &str = "UPDATE spans SET ended_at = ?2 WHERE id = ?1";

/// Closes every span left open by a crash or force quit. A row keeps its own
/// start when no frame is newer, so a stale open span never ends before it
/// began.
const CLOSE_OPEN_SPANS: &str = "
    UPDATE spans
    SET ended_at = MAX(started_at, COALESCE((SELECT MAX(captured_at) FROM frames), started_at))
    WHERE ended_at IS NULL";

const INSERT_REMINDER: &str = "
    INSERT INTO reminders (frame_id, created_at, due_at, note)
    VALUES (?1, ?2, ?3, ?4)";

const COMPLETE_REMINDER: &str = "UPDATE reminders SET done_at = ?2 WHERE id = ?1";

const UPSERT_SETTING: &str = "
    INSERT INTO settings (key, value) VALUES (?1, ?2)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value";

const INSERT_EXCLUDED_APP: &str = "INSERT OR IGNORE INTO excluded_apps (bundle_id) VALUES (?1)";

const REDUCE_SEGMENT: &str = "
    UPDATE segments SET tier = ?2, bytes = ?3
    WHERE id = ?1 AND path IS NOT NULL AND tier < ?4";

const SELECT_SEGMENT_EXISTS: &str = "SELECT 1 FROM segments WHERE id = ?1";

const SELECT_SEGMENT_PATH: &str = "SELECT path FROM segments WHERE id = ?1";

const DELETE_SEGMENT_VIDEO: &str = "
    UPDATE segments SET path = NULL, bytes = 0, tier = ?2 WHERE id = ?1";

/// Inserts the app row or updates its name when it changed, then returns the id.
fn upsert_app_in(connection: &Connection, bundle_id: &str, name: &str) -> Result<i64, StoreError> {
    connection
        .prepare_cached(UPSERT_APP)?
        .execute(params![bundle_id, name])?;
    let id = connection
        .prepare_cached(SELECT_APP_ID)?
        .query_row([bundle_id], |row| row.get(0))?;
    Ok(id)
}

/// The frame's window title as a line with no box, when it has text.
///
/// A title equal to one of the frame's own lines still gets its own row. The
/// key is `(frame_id, line_id, y, x)` and the title sits at (0, 0), so `INSERT
/// OR IGNORE` drops it only when the frame already holds that same text at that
/// exact place.
fn title_line(frame: &NewFrame) -> Option<NewLine> {
    let text = normalize_text(frame.window_title.as_deref()?);
    if text.is_empty() {
        return None;
    }
    Some(NewLine {
        text,
        x: 0,
        y: 0,
        w: 0,
        h: 0,
        source: LineSource::Title,
    })
}

impl Store {
    /// Inserts the app or updates its display name, returning the row id.
    pub fn upsert_app(&self, bundle_id: &str, name: &str) -> Result<i64, StoreError> {
        self.with_writer(|connection| upsert_app_in(connection, bundle_id, name))
    }

    /// Opens a segment row and returns its id. Video bytes are set on finish.
    pub fn begin_segment(
        &self,
        path: &str,
        started_at: i64,
        width: u32,
        height: u32,
    ) -> Result<i64, StoreError> {
        self.with_writer(|connection| {
            connection
                .prepare_cached(INSERT_SEGMENT)?
                .execute(params![path, started_at, width, height])?;
            Ok(connection.last_insert_rowid())
        })
    }

    /// Marks a segment closed and records the final video size.
    pub fn finish_segment(&self, id: i64, ended_at: i64, bytes: u64) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            let changed = connection.prepare_cached(FINISH_SEGMENT)?.execute(params![
                id,
                ended_at,
                u64_to_sql(bytes)
            ])?;
            if changed == 0 {
                return Err(StoreError::NotFound {
                    what: "segment",
                    id,
                });
            }
            Ok(())
        })
    }

    /// Stores a frame, its lines, and their positions in one transaction.
    ///
    /// Lines are normalized and deduplicated by hash across the whole database.
    /// The window title is stored as one more line, so a search finds the frame
    /// by the words in its title.
    pub fn insert_frame(&self, frame: &NewFrame) -> Result<i64, StoreError> {
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            let app_id = upsert_app_in(&transaction, &frame.bundle_id, &frame.app_name)?;
            transaction.prepare_cached(INSERT_FRAME)?.execute(params![
                frame.captured_at,
                frame.segment_id,
                frame.pts_ms,
                app_id,
                frame.window_title,
                frame.url,
                frame.change_ratio,
            ])?;
            let frame_id = transaction.last_insert_rowid();
            let title = title_line(frame);
            insert_frame_lines(
                &transaction,
                frame_id,
                frame.lines.iter().chain(title.iter()),
            )?;
            transaction.commit()?;
            Ok(frame_id)
        })
    }

    /// Opens a focus span, creating the app row when needed.
    pub fn begin_span(
        &self,
        bundle_id: &str,
        app_name: &str,
        window_title: Option<&str>,
        url: Option<&str>,
        started_at: i64,
    ) -> Result<i64, StoreError> {
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            let app_id = upsert_app_in(&transaction, bundle_id, app_name)?;
            transaction.prepare_cached(INSERT_SPAN)?.execute(params![
                app_id,
                window_title,
                url,
                started_at
            ])?;
            let id = transaction.last_insert_rowid();
            transaction.commit()?;
            Ok(id)
        })
    }

    /// Closes a focus span.
    pub fn end_span(&self, id: i64, ended_at: i64) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            let changed = connection
                .prepare_cached(END_SPAN)?
                .execute(params![id, ended_at])?;
            if changed == 0 {
                return Err(StoreError::NotFound { what: "span", id });
            }
            Ok(())
        })
    }

    /// Finishes every segment an earlier run left open and returns how many it finished.
    ///
    /// Call it before this run begins a segment: then every open segment belongs to a run that
    /// crashed or was killed. Each one ends at its newest frame, or at its start when it has
    /// none, and takes the size `file_bytes` reports for its relative path, so retention can
    /// reduce and delete it like any other segment.
    pub fn finish_unfinished_segments(
        &self,
        file_bytes: impl Fn(&str) -> u64,
    ) -> Result<u64, StoreError> {
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            let unfinished = {
                let mut statement = transaction.prepare_cached(SELECT_UNFINISHED_SEGMENTS)?;
                statement
                    .query_map([], |row| {
                        Ok((
                            row.get::<_, i64>(0)?,
                            row.get::<_, Option<String>>(1)?,
                            row.get::<_, i64>(2)?,
                        ))
                    })?
                    .collect::<Result<Vec<_>, _>>()?
            };
            {
                let mut finish = transaction.prepare_cached(FINISH_SEGMENT)?;
                for (id, path, ended_at) in &unfinished {
                    let bytes = path.as_deref().map_or(0, &file_bytes);
                    finish.execute(params![id, ended_at, u64_to_sql(bytes)])?;
                }
            }
            transaction.commit()?;
            Ok(u64::try_from(unfinished.len()).unwrap_or(u64::MAX))
        })
    }

    /// Closes every span still open after a crash or force quit.
    ///
    /// An open row would otherwise count as on screen until now in every
    /// report. Each open span ends at the newest kept frame, or at its own
    /// start when no frame is newer. Returns how many rows it closed. The engine
    /// calls this once when it opens.
    pub fn close_open_spans(&self) -> Result<u64, StoreError> {
        self.with_writer(|connection| {
            let closed = connection.prepare_cached(CLOSE_OPEN_SPANS)?.execute([])?;
            Ok(u64::try_from(closed).unwrap_or(u64::MAX))
        })
    }

    /// Saves a reminder, optionally anchored to a frame.
    pub fn add_reminder(
        &self,
        frame_id: Option<i64>,
        created_at: i64,
        due_at: i64,
        note: &str,
    ) -> Result<i64, StoreError> {
        self.with_writer(|connection| {
            connection
                .prepare_cached(INSERT_REMINDER)?
                .execute(params![frame_id, created_at, due_at, note])?;
            Ok(connection.last_insert_rowid())
        })
    }

    /// Marks a reminder done at `at`.
    pub fn complete_reminder(&self, id: i64, at: i64) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            let changed = connection
                .prepare_cached(COMPLETE_REMINDER)?
                .execute(params![id, at])?;
            if changed == 0 {
                return Err(StoreError::NotFound {
                    what: "reminder",
                    id,
                });
            }
            Ok(())
        })
    }

    /// Creates or replaces one setting.
    pub fn set_setting(&self, key: &str, value: &str) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            connection
                .prepare_cached(UPSERT_SETTING)?
                .execute(params![key, value])?;
            Ok(())
        })
    }

    /// Replaces the excluded app list with `bundle_ids`.
    pub fn set_excluded_apps(&self, bundle_ids: &[String]) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            let transaction = connection.transaction()?;
            transaction.execute("DELETE FROM excluded_apps", [])?;
            {
                let mut insert = transaction.prepare_cached(INSERT_EXCLUDED_APP)?;
                for bundle_id in bundle_ids {
                    insert.execute([bundle_id.as_str()])?;
                }
            }
            transaction.commit()?;
            Ok(())
        })
    }

    /// Records that retention shrunk a segment's video to `new_bytes` (tier 1).
    ///
    /// A segment without a video (tier 2 or a NULL path) is left untouched, so a
    /// stale retention action cannot revive bytes for a file that is gone.
    /// Returns [`StoreError::NotFound`] only when no segment has `id`.
    pub fn mark_segment_reduced(&self, id: i64, new_bytes: u64) -> Result<(), StoreError> {
        self.with_writer(|connection| {
            let changed = connection.prepare_cached(REDUCE_SEGMENT)?.execute(params![
                id,
                TIER_REDUCED,
                u64_to_sql(new_bytes),
                TIER_TEXT_ONLY
            ])?;
            if changed > 0 {
                return Ok(());
            }
            let exists: Option<i64> = connection
                .prepare_cached(SELECT_SEGMENT_EXISTS)?
                .query_row([id], |row| row.get(0))
                .optional()?;
            if exists.is_some() {
                return Ok(());
            }
            Err(StoreError::NotFound {
                what: "segment",
                id,
            })
        })
    }

    /// Deletes a segment's video row state (tier 2) and returns the old relative
    /// path so the caller can unlink the file. Returns `None` when the path was
    /// already gone.
    ///
    /// The path is also queued in `pending_unlinks` before the commit, so a
    /// crash before the unlink cannot lose it.
    pub fn delete_segment_video(&self, id: i64) -> Result<Option<String>, StoreError> {
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
            transaction
                .prepare_cached(DELETE_SEGMENT_VIDEO)?
                .execute(params![id, TIER_TEXT_ONLY])?;
            transaction.commit()?;
            Ok(path)
        })
    }
}
