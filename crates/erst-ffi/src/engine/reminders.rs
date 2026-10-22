//! Reminders: creating, listing due ones, and completing them.

use erst_core::now_ms;

use super::Engine;
use crate::convert;
use crate::error::ErstError;
use crate::records::FfiReminder;

#[uniffi::export]
impl Engine {
    /// Saves a reminder, anchored to a frame when one is given.
    pub fn add_reminder(
        &self,
        frame_id: Option<i64>,
        due_at_ms: i64,
        note: String,
    ) -> Result<i64, ErstError> {
        Ok(self
            .store
            .add_reminder(frame_id, now_ms(), due_at_ms, &note)?)
    }

    /// Open reminders due at or before `now_ms`, soonest first.
    pub fn due_reminders(&self, now_ms: i64) -> Result<Vec<FfiReminder>, ErstError> {
        Ok(self
            .store
            .due_reminders(now_ms)?
            .into_iter()
            .map(convert::reminder)
            .collect())
    }

    /// Marks a reminder done at `at_ms`.
    pub fn complete_reminder(&self, id: i64, at_ms: i64) -> Result<(), ErstError> {
        self.store.complete_reminder(id, at_ms)?;
        Ok(())
    }
}
