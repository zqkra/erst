//! Capture writes: keep decisions, segments, frames, and focus spans.

use std::sync::PoisonError;

use erst_core::FrameContext;

use super::Engine;
use crate::convert;
use crate::error::ErstError;
use crate::records::{FfiKeepDecision, FfiKeepReason, FfiNewFrame, FfiThumbnail};

#[uniffi::export]
impl Engine {
    /// Decides whether a thumbnail is worth keeping and remembers the last kept
    /// one. This never touches the database.
    pub fn evaluate_frame(
        &self,
        thumbnail: FfiThumbnail,
        now_ms: i64,
        focus_changed: bool,
    ) -> FfiKeepDecision {
        let Ok(next) = convert::thumbnail(thumbnail) else {
            // The FFI call has no error channel, so the reason says why nothing was
            // kept. The last kept frame stays as it was.
            return FfiKeepDecision {
                keep: false,
                change_ratio: 0.0,
                reason: FfiKeepReason::InvalidThumbnail,
            };
        };

        let mut memory = self
            .keep_memory
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let decision = {
            let previous = memory.last_kept.as_ref().map(|(thumbnail, _)| thumbnail);
            let last_kept_ms = memory.last_kept.as_ref().map(|(_, at_ms)| *at_ms);
            self.keep_policy.decide(
                previous,
                &next,
                &FrameContext {
                    now_ms,
                    last_kept_ms,
                    focus_changed,
                },
                memory.state,
            )
        };
        memory.state = decision.next_state;
        if decision.keep {
            memory.last_kept = Some((next, now_ms));
        }
        convert::keep_decision(decision)
    }

    /// Opens a segment row and returns its id.
    pub fn begin_segment(
        &self,
        relative_path: String,
        started_at_ms: i64,
        width: u32,
        height: u32,
    ) -> Result<i64, ErstError> {
        if relative_path.trim().is_empty() {
            return Err(ErstError::invalid("segment path must not be empty"));
        }
        Ok(self
            .store
            .begin_segment(&relative_path, started_at_ms, width, height)?)
    }

    /// Marks a segment closed and records its final video size.
    pub fn finish_segment(
        &self,
        segment_id: i64,
        ended_at_ms: i64,
        bytes: u64,
    ) -> Result<(), ErstError> {
        self.store.finish_segment(segment_id, ended_at_ms, bytes)?;
        Ok(())
    }

    /// Stores one kept frame, its focus metadata, and its text lines.
    pub fn record_frame(&self, frame: FfiNewFrame) -> Result<i64, ErstError> {
        Ok(self.store.insert_frame(&convert::new_frame(frame))?)
    }

    /// Starts a focus span and returns its id.
    pub fn begin_span(
        &self,
        bundle_id: String,
        app_name: String,
        window_title: Option<String>,
        url: Option<String>,
        started_at_ms: i64,
    ) -> Result<i64, ErstError> {
        Ok(self.store.begin_span(
            &bundle_id,
            &app_name,
            window_title.as_deref(),
            url.as_deref(),
            started_at_ms,
        )?)
    }

    /// Closes a focus span.
    pub fn end_span(&self, span_id: i64, ended_at_ms: i64) -> Result<(), ErstError> {
        self.store.end_span(span_id, ended_at_ms)?;
        Ok(())
    }
}
