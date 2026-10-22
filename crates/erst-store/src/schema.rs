//! Embedded migrations and connection pragmas.

use std::collections::HashMap;

use rusqlite::{Connection, params};

use crate::error::StoreError;
use crate::model::LineSource;
use crate::store::layout::{self, Placement};

/// The schema version this build writes and expects.
pub(crate) const LATEST_VERSION: u32 = 5;

/// Milliseconds a normal statement waits for a lock before failing.
pub(crate) const BUSY_TIMEOUT_MS: u64 = 5_000;

/// Bytes the WAL file keeps after a checkpoint: one automatic checkpoint's
/// worth, 1,000 pages of 4 KiB. Without a limit the file stays as large as the
/// largest transaction ever written, such as a migration.
const WAL_SIZE_LIMIT_BYTES: i64 = 4 * 1024 * 1024;

/// A migration step that SQL alone cannot express, run after its SQL in the
/// same transaction.
type Step = fn(&Connection) -> Result<(), StoreError>;

const MIGRATIONS: &[(u32, &str, Option<Step>)] = &[
    (1, include_str!("../migrations/0001_init.sql"), None),
    (
        2,
        include_str!("../migrations/0002_secure_delete.sql"),
        None,
    ),
    (
        3,
        include_str!("../migrations/0003_pending_unlinks.sql"),
        None,
    ),
    (4, include_str!("../migrations/0004_line_sources.sql"), None),
    (
        5,
        include_str!("../migrations/0005_frame_text.sql"),
        Some(pack_frame_lines),
    ),
];

/// Applies every migration newer than `user_version`, each in its own
/// transaction, then returns the pages a migration freed to the file system.
pub(crate) fn apply(connection: &mut Connection) -> Result<(), StoreError> {
    let current = user_version(connection)?;
    let mut migrated = false;
    for &(version, sql, step) in MIGRATIONS {
        if version <= current {
            continue;
        }
        let transaction = connection.transaction()?;
        transaction.execute_batch(sql)?;
        if let Some(step) = step {
            step(&transaction)?;
        }
        transaction.pragma_update(None, "user_version", version)?;
        transaction.commit()?;
        migrated = true;
    }
    if migrated {
        release_free_pages(connection)?;
        // A migration writes the whole database through the WAL; give that
        // space back now. Another process holding a snapshot only delays it.
        connection.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |_| Ok(()))?;
    }
    Ok(())
}

/// Returns every free page to the file system, so deleted rows stop taking
/// disk space.
///
/// `incremental_vacuum` frees one page per step, so it is stepped until done;
/// `execute_batch` steps a statement once and would free a single page.
pub(crate) fn release_free_pages(connection: &Connection) -> Result<(), StoreError> {
    let mut statement = connection.prepare("PRAGMA incremental_vacuum")?;
    let mut rows = statement.query([])?;
    while rows.next()?.is_some() {}
    Ok(())
}

/// Copies every `frame_lines` row into packed layouts and line runs, then drops
/// the table.
///
/// Frames are walked in id order, the order new frames are written in, and a
/// run continues while each next frame still shows its line, exactly as
/// [`crate::store`] grows runs on insert. A frame without lines ends every run.
fn pack_frame_lines(connection: &Connection) -> Result<(), StoreError> {
    let frame_ids: Vec<i64> = {
        let mut statement = connection.prepare("SELECT id FROM frames ORDER BY id")?;
        let rows = statement.query_map([], |row| row.get(0))?;
        rows.collect::<Result<_, _>>()?
    };
    let mut layouts: HashMap<i64, Vec<Placement>> = HashMap::new();
    {
        let mut statement =
            connection.prepare("SELECT frame_id, line_id, x, y, w, h, source FROM frame_lines")?;
        let mut rows = statement.query([])?;
        while let Some(row) = rows.next()? {
            layouts.entry(row.get(0)?).or_default().push(Placement {
                line_id: row.get(1)?,
                x: row.get(2)?,
                y: row.get(3)?,
                w: row.get(4)?,
                h: row.get(5)?,
                source: LineSource::from_code(row.get(6)?),
            });
        }
    }
    let mut insert_layout =
        connection.prepare("INSERT INTO frame_text (frame_id, layout) VALUES (?1, ?2)")?;
    let mut insert_run = connection
        .prepare("INSERT INTO line_runs (line_id, first_frame, last_frame) VALUES (?1, ?2, ?3)")?;
    let mut open: HashMap<i64, i64> = HashMap::new();
    let mut previous: Option<i64> = None;
    for frame_id in frame_ids {
        let placements = layouts.remove(&frame_id).unwrap_or_default();
        // A line can sit at two spots on one frame; it continues its run once.
        let mut continuing = HashMap::with_capacity(placements.len());
        for placement in &placements {
            continuing
                .entry(placement.line_id)
                .or_insert_with(|| open.remove(&placement.line_id).unwrap_or(frame_id));
        }
        if let Some(previous) = previous {
            for (line_id, first) in open.drain() {
                insert_run.execute(params![line_id, first, previous])?;
            }
        }
        open = continuing;
        if !placements.is_empty() {
            insert_layout.execute(params![frame_id, layout::encode(placements)])?;
        }
        previous = Some(frame_id);
    }
    if let Some(previous) = previous {
        for (line_id, first) in open {
            insert_run.execute(params![line_id, first, previous])?;
        }
    }
    connection.execute_batch("DROP TABLE frame_lines")?;
    Ok(())
}

/// Reads `PRAGMA user_version`, the migration cursor.
pub(crate) fn user_version(connection: &Connection) -> Result<u32, StoreError> {
    let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    Ok(u32::try_from(version).unwrap_or(0))
}

/// Pragmas for the connection that performs writes.
///
/// `auto_vacuum` comes first: switching to WAL materializes the database header,
/// and SQLite then refuses to change `auto_vacuum` on a schema that already
/// exists. Migrations run after this, so on a new database the pragma is in
/// place before the first table is created. `secure_delete` overwrites erased
/// content with zeros, which is what makes `erase_range` private.
pub(crate) fn apply_write_pragmas(connection: &Connection) -> Result<(), StoreError> {
    connection.pragma_update(None, "auto_vacuum", "INCREMENTAL")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    connection.pragma_update(None, "synchronous", "NORMAL")?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.pragma_update(None, "secure_delete", "ON")?;
    connection.pragma_update(None, "journal_size_limit", WAL_SIZE_LIMIT_BYTES)?;
    connection.busy_timeout(std::time::Duration::from_millis(BUSY_TIMEOUT_MS))?;
    Ok(())
}

/// Pragmas for a connection that only reads. `query_only` makes an accidental
/// write through it fail instead of silently taking the writer lock's job.
pub(crate) fn apply_reader_pragmas(connection: &Connection) -> Result<(), StoreError> {
    connection.pragma_update(None, "synchronous", "NORMAL")?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.busy_timeout(std::time::Duration::from_millis(BUSY_TIMEOUT_MS))?;
    connection.pragma_update(None, "query_only", "ON")?;
    Ok(())
}
