//! Erasing a time range: database rows first, then the segment videos.

use std::sync::PoisonError;

use super::{Engine, checked_range};
use crate::error::ErstError;
use crate::records::FfiEraseResult;

#[uniffi::export]
impl Engine {
    /// Erases everything recorded in `[start_ms, end_ms)` and reports what was
    /// removed.
    ///
    /// A video cannot be cut, so a segment that overlaps the range is removed
    /// whole with every frame it holds. Close the open segment with
    /// [`Engine::finish_segment`] before erasing a range that touches it. The
    /// next frame after an erase is always kept, even when it looks like an
    /// erased one.
    ///
    /// The erase succeeds once the database change commits. A video that cannot
    /// be deleted stays pending and is retried on the next open or retention
    /// pass. `purge_complete` is `false` while a reader still holds an old
    /// snapshot, so erased text may remain in the write-ahead log until the
    /// next erase.
    pub fn erase(&self, start_ms: i64, end_ms: i64) -> Result<FfiEraseResult, ErstError> {
        checked_range(start_ms, end_ms)?;
        let outcome = self.store.erase_range(start_ms, end_ms)?;
        self.keep_memory
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clear();
        self.drain_pending_unlinks();
        Ok(FfiEraseResult {
            frames_removed: outcome.frames_removed,
            erased_from_ms: outcome.erased_from_ms,
            erased_to_ms: outcome.erased_to_ms,
            purge_complete: outcome.purge_complete,
        })
    }
}
