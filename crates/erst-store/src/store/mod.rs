//! Store handle, opening, and connection access.

mod erase;
mod frame_text;
pub(crate) mod layout;
mod lines;
mod reads;
mod search;
mod writes;

#[cfg(test)]
mod tests;

use std::path::Path;
use std::sync::Mutex;

use rusqlite::{Connection, OpenFlags};

use crate::error::StoreError;
use crate::schema;

/// SQLite integers are signed. Byte counts and row counts stay far below
/// `i64::MAX`, so the conversions below are total in practice.
pub(crate) fn u64_to_sql(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

/// The inverse of [`u64_to_sql`] for a value read back from SQLite.
pub(crate) fn u64_from_sql(value: i64) -> u64 {
    u64::try_from(value).unwrap_or(0)
}

/// Comma-separated `?` placeholders for an `IN (...)` list of `count` values.
pub(crate) fn placeholders(count: usize) -> String {
    vec!["?"; count].join(",")
}

/// Queues one segment's relative video path for unlinking while its row still
/// exists, inside the transaction that detaches it.
pub(crate) const STAGE_SEGMENT_UNLINK: &str = "
    INSERT OR IGNORE INTO pending_unlinks (path)
    SELECT path FROM segments WHERE id = ?1 AND path IS NOT NULL";

/// SQLite-backed memory store with one writer and one reader connection.
///
/// Both connections live behind mutexes, so `Store` is `Send + Sync` and every
/// public method takes `&self`. A read-only store has no writer connection and
/// returns [`StoreError::ReadOnly`] from every write.
#[derive(Debug)]
pub struct Store {
    writer: Mutex<Option<Connection>>,
    reader: Mutex<Connection>,
}

impl Store {
    /// Opens or creates the database at `path`, creating parent directories.
    ///
    /// Runs any pending migrations on the writer connection before returning.
    /// Errors name the path that failed to open.
    pub fn open(path: &Path) -> Result<Self, StoreError> {
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
        {
            std::fs::create_dir_all(parent).map_err(|source| StoreError::CreateDirectory {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        let mut writer = Connection::open(path).map_err(|source| StoreError::OpenDatabase {
            path: path.to_path_buf(),
            source,
        })?;
        schema::apply_write_pragmas(&writer)?;
        schema::apply(&mut writer)?;
        let reader = Connection::open(path).map_err(|source| StoreError::OpenDatabase {
            path: path.to_path_buf(),
            source,
        })?;
        schema::apply_reader_pragmas(&reader)?;
        Ok(Self {
            writer: Mutex::new(Some(writer)),
            reader: Mutex::new(reader),
        })
    }

    /// Opens an existing database without running migrations.
    ///
    /// Returns [`StoreError::SchemaTooOld`] when the stored schema is behind this
    /// build. The connection refuses writes at the SQLite level as well.
    pub fn open_read_only(path: &Path) -> Result<Self, StoreError> {
        let reader = Connection::open_with_flags(
            path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|source| StoreError::OpenDatabase {
            path: path.to_path_buf(),
            source,
        })?;
        schema::apply_reader_pragmas(&reader)?;
        let found = schema::user_version(&reader)?;
        if found < schema::LATEST_VERSION {
            return Err(StoreError::SchemaTooOld {
                found,
                expected: schema::LATEST_VERSION,
            });
        }
        Ok(Self {
            writer: Mutex::new(None),
            reader: Mutex::new(reader),
        })
    }

    fn with_writer<T>(
        &self,
        action: impl FnOnce(&mut Connection) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let mut guard = self.writer.lock().map_err(|_| StoreError::Poisoned)?;
        let connection = guard.as_mut().ok_or(StoreError::ReadOnly)?;
        action(connection)
    }

    fn with_reader<T>(
        &self,
        action: impl FnOnce(&Connection) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let guard = self.reader.lock().map_err(|_| StoreError::Poisoned)?;
        action(&guard)
    }
}
