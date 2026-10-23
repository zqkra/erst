//! Row and parameter types shared with the rest of Erst.
//!
//! `erst-store` owns these instead of depending on `erst-core`; the FFI layer maps
//! between the two sets of types.

/// Where a frame line came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LineSource {
    /// Read from the pixels by text recognition.
    Ocr,
    /// Read from the focused window's accessibility tree, so the text is exact.
    Accessibility,
    /// The frame's window title. It has no box on the frame.
    Title,
}

impl LineSource {
    /// The code stored with each placement in a frame layout.
    pub(crate) const fn code(self) -> i64 {
        match self {
            Self::Ocr => 0,
            Self::Accessibility => 1,
            Self::Title => 2,
        }
    }

    /// Reads a stored code. An unknown code reads as OCR, which is what every
    /// line written before the column existed is.
    pub(crate) const fn from_code(code: i64) -> Self {
        match code {
            1 => Self::Accessibility,
            2 => Self::Title,
            _ => Self::Ocr,
        }
    }
}

/// One text line detected on a frame, before storage.
#[derive(Debug, Clone, PartialEq)]
pub struct NewLine {
    pub text: String,
    /// Left edge, normalized to the frame width and scaled to 0..=10000.
    pub x: u16,
    /// Top edge, normalized to the frame height and scaled to 0..=10000.
    pub y: u16,
    /// Width, normalized to the frame width and scaled to 0..=10000.
    pub w: u16,
    /// Height, normalized to the frame height and scaled to 0..=10000.
    pub h: u16,
    /// Where the text came from.
    pub source: LineSource,
}

/// A kept frame and the text lines read from it.
#[derive(Debug, Clone, PartialEq)]
pub struct NewFrame {
    pub captured_at: i64,
    pub segment_id: i64,
    /// Presentation time inside the segment.
    pub pts_ms: i64,
    pub bundle_id: String,
    pub app_name: String,
    pub window_title: Option<String>,
    pub url: Option<String>,
    pub change_ratio: f32,
    pub lines: Vec<NewLine>,
}

/// A stored text line with its position on the frame.
#[derive(Debug, Clone, PartialEq)]
pub struct LineBox {
    pub text: String,
    pub x: u16,
    pub y: u16,
    pub w: u16,
    pub h: u16,
    pub source: LineSource,
}

/// The identity and recency of a stored frame.
#[derive(Debug, Clone, PartialEq)]
pub struct FrameStamp {
    pub id: i64,
    pub captured_at: i64,
    pub change_ratio: f32,
}

/// One kept frame with the app, window title, and page it showed, for the timeline track.
#[derive(Debug, Clone, PartialEq)]
pub struct TrackFrameRow {
    pub id: i64,
    pub captured_at: i64,
    pub change_ratio: f32,
    pub bundle_id: Option<String>,
    pub app_name: Option<String>,
    pub window_title: Option<String>,
    pub url: Option<String>,
}

/// A segment an earlier run left open, finished when the store opened again.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveredSegment {
    pub id: i64,
    /// Relative to the data directory; `None` once retention removed the video.
    pub path: Option<String>,
}

/// What one erase removed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EraseOutcome {
    /// Frames deleted, including frames of removed segments outside the range.
    pub frames_removed: u64,
    /// Relative paths of segment videos the caller must delete from disk.
    pub segment_paths: Vec<String>,
    /// Start of the erased range in Unix milliseconds.
    pub erased_from_ms: i64,
    /// End of the erased range in Unix milliseconds.
    pub erased_to_ms: i64,
    /// Whether the post-commit vacuum and WAL truncation completed.
    ///
    /// `false` means a reader still held a snapshot, so the row changes and the
    /// pending unlinks are durable but erased bytes can remain in the WAL. A
    /// later erase retries the purge. An empty range reports `true`: it removed
    /// nothing, so nothing is waiting.
    pub purge_complete: bool,
}

/// Which access plan search uses to turn matched lines into frames.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchPlan {
    /// Read the matched line ids and pick the cheaper plan.
    Auto,
    /// Walk frames newest first and probe their lines. Best for common terms,
    /// where the first `limit` hits sit near the newest frames.
    FrameScan,
    /// Walk the matched lines to their frames through `line_runs`.
    /// Best for rare terms, where scanning months of frames would be wasted
    /// work.
    LineDriven,
}

/// A ready FTS5 MATCH expression plus filters and a result cap.
#[derive(Debug, Clone, PartialEq)]
pub struct SearchParams {
    /// Built by `erst-core::query`; passed through to FTS5 unchanged.
    pub fts_match: String,
    /// Matched case-insensitively against the app name or the bundle id.
    pub app: Option<String>,
    pub since_ms: Option<i64>,
    pub until_ms: Option<i64>,
    pub limit: u32,
}

/// A moment: consecutive matching frames of the same app and window.
#[derive(Debug, Clone, PartialEq)]
pub struct SearchHit {
    pub frame_id: i64,
    pub captured_at: i64,
    pub first_seen_ms: i64,
    pub last_seen_ms: i64,
    pub bundle_id: String,
    pub app_name: String,
    pub window_title: Option<String>,
    pub url: Option<String>,
    pub segment_path: Option<String>,
    pub pts_ms: i64,
    /// Matched lines on the representative frame, ordered by `y` then `x`.
    pub matched_lines: Vec<LineBox>,
}

/// A focus span: one app and window staying on screen.
#[derive(Debug, Clone, PartialEq)]
pub struct SpanRow {
    pub id: i64,
    pub bundle_id: String,
    pub app_name: String,
    pub window_title: Option<String>,
    pub url: Option<String>,
    pub started_at: i64,
    pub ended_at: Option<i64>,
}

/// A stored frame plus everything needed to show it.
#[derive(Debug, Clone, PartialEq)]
pub struct FrameDetail {
    pub stamp: FrameStamp,
    pub bundle_id: String,
    pub app_name: String,
    pub window_title: Option<String>,
    pub url: Option<String>,
    pub segment_id: i64,
    pub segment_path: Option<String>,
    pub segment_started_at: i64,
    pub pts_ms: i64,
    pub tier: u8,
    pub lines: Vec<LineBox>,
}

/// A video segment row, including retention state.
#[derive(Debug, Clone, PartialEq)]
pub struct SegmentRow {
    pub id: i64,
    pub path: Option<String>,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub width: u32,
    pub height: u32,
    pub bytes: u64,
    /// 0 full, 1 reduced, 2 text only.
    pub tier: u8,
}

/// Aggregate storage facts for the storage screen.
#[derive(Debug, Clone, PartialEq)]
pub struct StorageStats {
    /// Sum of the recorded size of every segment. Deleted videos count as zero.
    pub video_bytes: u64,
    /// Main database size: SQLite's page count times page size.
    pub database_bytes: u64,
    pub segment_count: u64,
    pub frame_count: u64,
    pub unique_line_count: u64,
    pub oldest_ms: Option<i64>,
    pub newest_ms: Option<i64>,
    /// Bytes of segments started within 24 hours before the caller's `now_ms`.
    pub video_bytes_last_24h: u64,
}

/// A reminder, optionally anchored to a frame.
#[derive(Debug, Clone, PartialEq)]
pub struct ReminderRow {
    pub id: i64,
    pub frame_id: Option<i64>,
    pub created_at: i64,
    pub due_at: i64,
    pub note: String,
    pub done_at: Option<i64>,
}
