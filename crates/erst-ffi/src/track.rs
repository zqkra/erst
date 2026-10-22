//! Records for the timeline track: the frame-indexed timeline scrubber.
//!
//! The track draws every kept frame at the same width and groups consecutive
//! frames of one app (and one site for browsers) into a segment that starts
//! with the app icon.

/// The frames and segments of one range, already grouped for the track.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiTrack {
    /// Inclusive range start in Unix milliseconds.
    pub start_ms: i64,
    /// Exclusive range end in Unix milliseconds.
    pub end_ms: i64,
    /// Kept frames inside the range, oldest first.
    pub frames: Vec<FfiTrackFrame>,
    /// Consecutive runs of frames sharing an app and site, in time order.
    pub segments: Vec<FfiTrackSegment>,
}

/// One kept frame of the track and the segment it belongs to.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiTrackFrame {
    /// Frame id.
    pub id: i64,
    /// Capture time in Unix milliseconds.
    pub captured_at_ms: i64,
    /// Share of the screen that changed since the previous kept frame, `0.0..=1.0`.
    pub change_ratio: f32,
    /// Index of the segment this frame belongs to.
    pub segment: u32,
}

/// One app and site run the track draws as a single segment.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiTrackSegment {
    /// Bundle identifier of the app, `""` when the frame had none.
    pub bundle_id: String,
    /// Display name of the app, `"Unknown"` when the frame had none.
    pub app_name: String,
    /// Window title of the segment's last frame, trimmed, `None` when it had none.
    pub title: Option<String>,
    /// Site host for browser frames, `None` otherwise.
    pub host: Option<String>,
    /// Index in `frames` of the first frame, inclusive.
    pub first_frame: u32,
    /// Index in `frames` of the last frame, inclusive.
    pub last_frame: u32,
    /// Capture time of the first frame in Unix milliseconds.
    pub started_at_ms: i64,
    /// Capture time of the last frame in Unix milliseconds.
    pub ended_at_ms: i64,
    /// True for the first segment and after a pause longer than the session gap.
    pub starts_session: bool,
}
