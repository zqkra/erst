//! Frames a video file never got: the newest frame of a segment an interrupted run left open.

use std::sync::PoisonError;

use super::Engine;
use crate::convert;
use crate::error::ErstError;
use crate::records::FfiSegmentVideo;

#[uniffi::export]
impl Engine {
    /// The segments this engine finished when it opened, because an earlier run crashed or was
    /// killed with them open, with absolute video paths.
    ///
    /// The app reads where each file's video ends and calls
    /// [`Engine::drop_unwritten_frames`] for the frames past it.
    pub fn recovered_segments(&self) -> Vec<FfiSegmentVideo> {
        self.recovered
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .iter()
            .filter_map(|segment| self.video(segment.id, segment.path.as_deref()))
            .collect()
    }

    /// Every finished segment that still has a video, oldest first, for a one-time check of
    /// history recorded before interrupted runs were repaired at open.
    pub fn finished_segment_videos(&self) -> Result<Vec<FfiSegmentVideo>, ErstError> {
        let mut segments = self.store.segments()?;
        segments.retain(|segment| segment.ended_at.is_some());
        segments.reverse();
        Ok(segments
            .iter()
            .filter_map(|segment| self.video(segment.id, segment.path.as_deref()))
            .collect())
    }

    /// Drops the frames of a finished segment at or after `written_until_ms`, the end of the
    /// video its file holds, and returns how many it dropped.
    ///
    /// The open segment is refused: its newest frames are still on their way into the file.
    pub fn drop_unwritten_frames(
        &self,
        segment_id: i64,
        written_until_ms: i64,
    ) -> Result<u64, ErstError> {
        if self
            .store
            .open_segment()?
            .is_some_and(|open| open.id == segment_id)
        {
            return Err(ErstError::invalid(format!(
                "segment {segment_id} is still being written"
            )));
        }
        Ok(self
            .store
            .drop_unwritten_frames(segment_id, written_until_ms)?)
    }
}

impl Engine {
    fn video(&self, segment_id: i64, path: Option<&str>) -> Option<FfiSegmentVideo> {
        convert::absolute_path(self.data_dir(), path)
            .map(|path| FfiSegmentVideo { segment_id, path })
    }
}
