//! The timeline track: frames of a range grouped into app and site segments.

use erst_core::{SegmentKey, TrackSegment, group_segments, url_host};
use erst_store::TrackFrameRow;

use super::{Engine, checked_range};
use crate::error::ErstError;
use crate::track::{FfiTrack, FfiTrackFrame, FfiTrackSegment};

/// Frames one track request may return.
///
/// The app loads a few days at a time; a range with more frames than this is
/// refused before its records are built instead of crossing the FFI in one go.
const MAX_TRACK_FRAMES: usize = 200_000;

/// App name shown for a frame whose app row is missing or has no name.
const UNKNOWN_APP_NAME: &str = "Unknown";

#[uniffi::export]
impl Engine {
    /// Frames of `[start_ms, end_ms)` grouped into app and site segments for the timeline track.
    ///
    /// A frame joins the segment of the previous one when the app, and the site
    /// for a browser URL, is the same and the pause is at most the session gap.
    /// A longer pause starts a new session, which the track draws as a wider
    /// gap. `frames[i].segment` indexes `segments`, and a segment's
    /// `first_frame` and `last_frame` index `frames` with `first_frame <= i <=
    /// last_frame` for every frame of that segment.
    pub fn timeline_track(&self, start_ms: i64, end_ms: i64) -> Result<FfiTrack, ErstError> {
        let range = checked_range(start_ms, end_ms)?;
        let rows = self.store.track_frames(range.start_ms, range.end_ms)?;
        check_frame_count(rows.len())?;
        let keys: Vec<(i64, SegmentKey)> = rows
            .iter()
            .map(|row| (row.captured_at, segment_key(row)))
            .collect();
        let segments = group_segments(&keys);
        Ok(FfiTrack {
            start_ms,
            end_ms,
            frames: track_frames(&rows, &segments),
            segments: track_segments(&rows, &segments),
        })
    }
}

fn check_frame_count(count: usize) -> Result<(), ErstError> {
    if count > MAX_TRACK_FRAMES {
        return Err(ErstError::invalid(format!(
            "range holds {count} frames, more than {MAX_TRACK_FRAMES}; ask for a shorter range"
        )));
    }
    Ok(())
}

/// The app, and for a browser URL the site, a frame belongs to.
///
/// The capture layer reads a URL only from a browser window, so a stored URL is
/// the evidence of a site and no browser bundle list is repeated here.
fn segment_key(row: &TrackFrameRow) -> SegmentKey {
    SegmentKey {
        bundle_id: row.bundle_id.clone().unwrap_or_default(),
        host: row.url.as_deref().and_then(url_host),
    }
}

fn track_frames(rows: &[TrackFrameRow], segments: &[TrackSegment]) -> Vec<FfiTrackFrame> {
    let mut frames = Vec::with_capacity(rows.len());
    let mut cursor = 0_usize;
    for (index, row) in rows.iter().enumerate() {
        while segments
            .get(cursor)
            .is_some_and(|segment| segment.last_index < index)
        {
            cursor += 1;
        }
        frames.push(FfiTrackFrame {
            id: row.id,
            captured_at_ms: row.captured_at,
            change_ratio: row.change_ratio,
            segment: u32::try_from(cursor).unwrap_or(u32::MAX),
        });
    }
    frames
}

fn track_segments(rows: &[TrackFrameRow], segments: &[TrackSegment]) -> Vec<FfiTrackSegment> {
    segments
        .iter()
        .map(|segment| FfiTrackSegment {
            bundle_id: segment.key.bundle_id.clone(),
            app_name: app_name(rows.get(segment.first_index)),
            title: segment_title(rows.get(segment.last_index)),
            host: segment.key.host.clone(),
            first_frame: u32::try_from(segment.first_index).unwrap_or(u32::MAX),
            last_frame: u32::try_from(segment.last_index).unwrap_or(u32::MAX),
            started_at_ms: segment.started_at_ms,
            ended_at_ms: segment.ended_at_ms,
            starts_session: segment.starts_session,
        })
        .collect()
}

fn app_name(row: Option<&TrackFrameRow>) -> String {
    row.and_then(|row| row.app_name.as_deref())
        .filter(|name| !name.is_empty())
        .unwrap_or(UNKNOWN_APP_NAME)
        .to_owned()
}

/// The window title a segment is labelled with: the one of its last frame, which
/// is the state the user last saw there, not the one it started with.
fn segment_title(row: Option<&TrackFrameRow>) -> Option<String> {
    row.and_then(|row| row.window_title.as_deref())
        .map(str::trim)
        .filter(|title| !title.is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::{MAX_TRACK_FRAMES, check_frame_count};

    #[test]
    fn a_range_at_the_frame_limit_is_accepted_and_more_is_refused() {
        assert!(check_frame_count(0).is_ok());
        assert!(check_frame_count(MAX_TRACK_FRAMES).is_ok());
        assert!(check_frame_count(MAX_TRACK_FRAMES + 1).is_err());
    }
}
