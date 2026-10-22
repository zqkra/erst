//! Where the database lives and how it is opened.

use std::io;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use erst_store::Store;

/// Environment override checked when `--data-dir` is absent.
pub const DATA_DIR_ENV: &str = "ERST_DATA_DIR";
/// Database file inside the data directory.
pub const DATABASE_FILE: &str = "erst.sqlite";

/// Resolves the data directory: flag, then environment, then the macOS default.
pub fn resolve(flag: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = flag {
        return Ok(path);
    }
    if let Some(value) = std::env::var_os(DATA_DIR_ENV)
        && !value.is_empty()
    {
        return Ok(PathBuf::from(value));
    }
    let home = std::env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .context("HOME is not set; pass --data-dir or set ERST_DATA_DIR")?;
    Ok(PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Erst"))
}

/// Path of the SQLite file inside `data_dir`.
pub fn database_path(data_dir: &Path) -> PathBuf {
    data_dir.join(DATABASE_FILE)
}

/// Opens the database read only. A missing file is a `NotFound` IO error.
pub fn open(data_dir: &Path) -> Result<Store> {
    let path = database_path(data_dir);
    if !path.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!(
                "no Erst database at {} (run Erst once to start recording, or pass --data-dir)",
                path.display()
            ),
        )
        .into());
    }
    Store::open_read_only(&path).with_context(|| format!("could not open {}", path.display()))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use std::path::Path;

    use super::database_path;

    #[test]
    fn database_sits_inside_the_data_directory() {
        assert_eq!(
            database_path(Path::new("/tmp/erst")),
            Path::new("/tmp/erst/erst.sqlite")
        );
    }
}
