//! The one error type for every store operation.

use std::path::PathBuf;

use thiserror::Error;

/// Everything that can go wrong inside the store.
#[derive(Debug, Error)]
pub enum StoreError {
    #[error("sqlite: {0}")]
    Sqlite(rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("cannot create directory {path}: {source}")]
    CreateDirectory {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("cannot open database {path}: {source}")]
    OpenDatabase {
        path: PathBuf,
        #[source]
        source: rusqlite::Error,
    },
    #[error("no {what} with id {id}")]
    NotFound { what: &'static str, id: i64 },
    #[error("database schema version {found} does not match expected {expected}")]
    SchemaTooOld { found: u32, expected: u32 },
    #[error("store is read-only")]
    ReadOnly,
    #[error("store lock poisoned")]
    Poisoned,
    #[error("wal checkpoint is busy: a reader still holds a snapshot")]
    CheckpointBusy,
    #[error("invalid frame layout: {0}")]
    InvalidLayout(&'static str),
}

impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> Self {
        if let rusqlite::Error::SqliteFailure(failure, _) = &error
            && failure.code == rusqlite::ErrorCode::ReadOnly
        {
            return Self::ReadOnly;
        }
        Self::Sqlite(error)
    }
}
