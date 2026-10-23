//! The `Engine` object Swift holds, and the scaffolding shared by its methods.
//!
//! Methods are grouped in submodules by area: capture writes, queries, erasing,
//! settings, retention, and reminders. The struct itself owns the data
//! directory, the store, the keep policy, and the last kept thumbnail. It also
//! deletes segment videos, which both erase and retention need.

mod capture;
mod erase;
mod queries;
mod recovery;
mod reminders;
mod retention;
mod settings;
mod track;

use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use erst_core::{KeepPolicy, KeepState, Thumbnail, TimeRange};
use erst_store::{RecoveredSegment, Store};

use crate::error::ErstError;

/// Database file name inside the data directory.
const DATABASE_FILE_NAME: &str = "erst.sqlite";

/// Directory that holds segment videos inside the data directory.
const SEGMENTS_DIR_NAME: &str = "segments";

/// What the keep policy remembers between frames.
///
/// The last kept thumbnail and the motion run live under one lock so a decision
/// always sees both from the same kept frame. Erasing a range clears both, which
/// makes the next frame a first frame.
#[derive(Debug, Default)]
struct KeepMemory {
    last_kept: Option<(Thumbnail, i64)>,
    state: KeepState,
}

impl KeepMemory {
    fn clear(&mut self) {
        *self = Self::default();
    }
}

/// The state Swift holds for one Erst data directory.
#[derive(Debug, uniffi::Object)]
pub struct Engine {
    data_dir: PathBuf,
    store: Store,
    keep_policy: KeepPolicy,
    keep_memory: Mutex<KeepMemory>,
    /// The segments this open finished for a run that crashed or was killed.
    recovered: Mutex<Vec<RecoveredSegment>>,
}

#[uniffi::export]
impl Engine {
    /// Opens the engine rooted at `data_dir`, creating the directory layout and
    /// the database when they are missing.
    ///
    /// A span left open by an earlier run ends at the newest kept frame, a
    /// segment left open by a crash or a kill is finished with its newest frame
    /// and its size on disk, and videos detached by an earlier run that could
    /// not delete them are retried.
    #[uniffi::constructor]
    pub fn open(data_dir: String) -> Result<Arc<Self>, ErstError> {
        if data_dir.trim().is_empty() {
            return Err(ErstError::invalid("data directory must not be empty"));
        }

        let data_dir = PathBuf::from(data_dir);
        if data_dir.exists() && !data_dir.is_dir() {
            return Err(ErstError::invalid(format!(
                "data directory {} exists and is not a directory",
                data_dir.display()
            )));
        }

        let engine = Self {
            store: Store::open(&data_dir.join(DATABASE_FILE_NAME))?,
            data_dir,
            keep_policy: KeepPolicy::default(),
            keep_memory: Mutex::new(KeepMemory::default()),
            recovered: Mutex::new(Vec::new()),
        };
        engine.create_segments_dir()?;
        engine.store.close_open_spans()?;
        let recovered = engine.finish_unfinished_segments()?;
        *engine
            .recovered
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = recovered;
        engine.drain_pending_unlinks();
        Ok(Arc::new(engine))
    }

    /// The version of the Rust core, shown in the app to prove the pipeline links.
    pub fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").to_owned()
    }

    /// How many deleted videos still wait for their file to be removed.
    ///
    /// An erase or retention pass that cannot delete a file keeps its path in
    /// `pending_unlinks`, and the next `open`, `retention_plan`, or
    /// `apply_retention` retries it. The app reports a count above zero so a
    /// stuck deletion is visible.
    pub fn pending_file_count(&self) -> Result<u64, ErstError> {
        let pending = self.store.pending_unlinks()?.len();
        Ok(u64::try_from(pending).unwrap_or(u64::MAX))
    }
}

impl Engine {
    /// Creates `data_dir/segments`.
    fn create_segments_dir(&self) -> Result<(), ErstError> {
        let segments_dir = self.data_dir.join(SEGMENTS_DIR_NAME);
        fs::create_dir_all(&segments_dir).map_err(|error| ErstError::io(&segments_dir, error))
    }

    /// Finishes the segments an earlier run left open, sized from their files.
    ///
    /// It runs before this run begins a segment, so every open segment is stale.
    /// A missing file counts as zero bytes.
    fn finish_unfinished_segments(&self) -> Result<Vec<RecoveredSegment>, ErstError> {
        let data_dir = &self.data_dir;
        Ok(self.store.finish_unfinished_segments(|relative_path| {
            fs::metadata(data_dir.join(relative_path)).map_or(0, |metadata| metadata.len())
        })?)
    }

    /// The data directory every stored relative path resolves against.
    pub(crate) fn data_dir(&self) -> &Path {
        &self.data_dir
    }

    /// Deletes a stored video, treating an already missing file as success.
    fn remove_video(&self, relative_path: &str) -> Result<(), ErstError> {
        let path = Path::new(relative_path);
        let absolute = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.data_dir().join(path)
        };
        match fs::remove_file(&absolute) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(ErstError::io(&absolute, error)),
        }
    }

    /// Deletes the videos the store has detached, forgetting each path once its
    /// file is gone.
    ///
    /// A file that cannot be deleted stays pending, so the next open or
    /// retention pass tries it again, and [`Engine::pending_file_count`] tells
    /// the app how many are left. The database change has already committed, so
    /// a failure here changes nothing else.
    pub(crate) fn drain_pending_unlinks(&self) {
        let Ok(pending) = self.store.pending_unlinks() else {
            return;
        };
        for relative_path in pending {
            if self.remove_video(&relative_path).is_err() {
                continue;
            }
            let _ = self.store.unlink_done(&relative_path);
        }
    }
}

/// Validates a range that arrives as two separate arguments.
pub(crate) fn checked_range(start_ms: i64, end_ms: i64) -> Result<TimeRange, ErstError> {
    TimeRange::new(start_ms, end_ms)
        .ok_or_else(|| ErstError::invalid("range end precedes its start"))
}
