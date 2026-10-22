//! Retention planning and applying one action.

use erst_core::{MS_PER_DAY, RetentionPolicy, SegmentInfo};

use super::Engine;
use crate::convert;
use crate::error::ErstError;
use crate::records::{FfiRetentionAction, FfiRetentionKind};
use crate::settings::{BYTES_PER_GIGABYTE, MS_PER_MONTH};

#[uniffi::export]
impl Engine {
    /// Plans retention work for closed segments at `now_ms`.
    ///
    /// Videos detached by an earlier run are deleted first. The open segment is
    /// left out of the plan, so it can never receive an action even when it is
    /// not the newest row. When the user chose to delete everything after the
    /// lighter copy period, segments past that period come back as
    /// [`FfiRetentionKind::DeleteSegment`], text-only ones included. Deletions
    /// forced by the storage budget keep the text.
    pub fn retention_plan(&self, now_ms: i64) -> Result<Vec<FfiRetentionAction>, ErstError> {
        self.drain_pending_unlinks();
        let settings = self.load_settings()?;
        let policy = RetentionPolicy {
            full_quality_ms: i64::from(settings.full_quality_days).saturating_mul(MS_PER_DAY),
            reduced_ms: settings
                .lighter_copy_months
                .map(|months| i64::from(months).saturating_mul(MS_PER_MONTH)),
            budget_bytes: settings
                .storage_limit_gigabytes
                .map(|gigabytes| u64::from(gigabytes).saturating_mul(BYTES_PER_GIGABYTE)),
            after_lighter_copy: convert::after_lighter_copy(settings.after_lighter_copy),
        };

        let open_id = self.store.open_segment()?.map(|segment| segment.id);
        let segments: Vec<erst_store::SegmentRow> = self
            .store
            .segments()?
            .into_iter()
            .filter(|segment| segment.ended_at.is_some() && Some(segment.id) != open_id)
            .collect();
        let infos: Vec<SegmentInfo> = segments.iter().map(convert::segment_info).collect();

        Ok(erst_core::plan(&policy, &infos, now_ms)
            .into_iter()
            .map(|action| {
                let segment_path = segments
                    .iter()
                    .find(|segment| segment.id == action.segment_id)
                    .and_then(|segment| {
                        convert::absolute_path(self.data_dir(), segment.path.as_deref())
                    });
                FfiRetentionAction {
                    segment_id: action.segment_id,
                    kind: convert::retention_kind(action.action),
                    segment_path,
                }
            })
            .collect())
    }

    /// Performs the database side of a retention action, then deletes the video
    /// file when the action removes it.
    ///
    /// [`FfiRetentionKind::DeleteSegment`] also removes every frame of the
    /// segment and the text lines they leave orphaned. `new_bytes` is required
    /// for [`FfiRetentionKind::Reduce`] and ignored for the deletions. A video
    /// that cannot be deleted stays pending and does not fail the call.
    pub fn apply_retention(
        &self,
        action: FfiRetentionAction,
        new_bytes: Option<u64>,
    ) -> Result<(), ErstError> {
        match action.kind {
            FfiRetentionKind::Reduce => {
                let Some(new_bytes) = new_bytes else {
                    return Err(ErstError::invalid(
                        "reducing a segment needs its new size in bytes",
                    ));
                };
                self.store
                    .mark_segment_reduced(action.segment_id, new_bytes)?;
            }
            FfiRetentionKind::DeleteVideo => {
                self.store.delete_segment_video(action.segment_id)?;
                self.drain_pending_unlinks();
            }
            FfiRetentionKind::DeleteSegment => {
                self.store.delete_segment(action.segment_id)?;
                self.drain_pending_unlinks();
            }
        }
        Ok(())
    }
}
