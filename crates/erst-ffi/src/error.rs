//! The one error type Swift receives.
//!
//! Store and core errors are mapped here with enough context to name what
//! failed. No engine method panics on bad input; every failure becomes an
//! [`ErstError`].

use std::path::Path;

use erst_core::CoreError;
use erst_store::StoreError;
use thiserror::Error;

/// Errors surfaced to Swift as one UniFFI error enum.
#[derive(Debug, Error, uniffi::Error)]
pub enum ErstError {
    /// The file system could not be read or written.
    #[error("I/O error: {message}")]
    Io {
        /// Path and operating system message.
        message: String,
    },

    /// The database could not be opened or queried.
    #[error("Database error: {message}")]
    Database {
        /// The store message.
        message: String,
    },

    /// A caller supplied value is not valid.
    #[error("Invalid input: {message}")]
    InvalidInput {
        /// What is wrong with the value.
        message: String,
    },

    /// The requested item does not exist.
    #[error("Not found: {message}")]
    NotFound {
        /// What was looked up.
        message: String,
    },
}

impl ErstError {
    /// Turns an I/O failure into an error that names the path that failed.
    pub(crate) fn io(path: &Path, error: std::io::Error) -> Self {
        Self::Io {
            message: format!("{}: {error}", path.display()),
        }
    }

    /// Builds an invalid input error from a static explanation.
    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self::InvalidInput {
            message: message.into(),
        }
    }
}

impl From<StoreError> for ErstError {
    fn from(error: StoreError) -> Self {
        match error {
            StoreError::NotFound { what, id } => Self::NotFound {
                message: format!("no {what} with id {id}"),
            },
            StoreError::Io(error) => Self::Io {
                message: error.to_string(),
            },
            other => Self::Database {
                message: other.to_string(),
            },
        }
    }
}

impl From<CoreError> for ErstError {
    fn from(error: CoreError) -> Self {
        Self::InvalidInput {
            message: error.to_string(),
        }
    }
}
