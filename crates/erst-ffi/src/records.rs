//! Records and enums exchanged with Swift.
//!
//! Everything here is a plain value type: UniFFI turns each record into a Swift
//! struct with camelCase fields and each enum into a Swift enum. Timestamps are
//! Unix milliseconds, and text boxes are normalized to `0..=10000` with a
//! top-left origin.

use serde::{Deserialize, Serialize};

/// A downsampled grayscale frame, one luma byte per pixel.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiThumbnail {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Row-major luma samples, `width * height` bytes.
    pub luma: Vec<u8>,
}

/// Why the keep policy decided to keep or skip a frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum FfiKeepReason {
    /// A minor change was kept after the minor gap.
    Changed,
    /// The focused app or window changed.
    FocusChanged,
    /// The maximum gap since the last kept frame elapsed.
    MaxGap,
    /// There was no earlier frame to compare against.
    FirstFrame,
    /// The frame looks like the previous one.
    Unchanged,
    /// The change reached the major ratio, so the frame was kept at once.
    MajorChanged,
    /// A minor change arrived before the minor gap passed, so it was skipped.
    MinorDeferred,
    /// Continuous motion is throttled to one keep per motion gap.
    MotionThrottled,
    /// The thumbnail did not match its size, so nothing was compared.
    InvalidThumbnail,
}

/// The outcome of comparing one frame against the last kept one.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiKeepDecision {
    /// Whether this frame should be written.
    pub keep: bool,
    /// Fraction of compared tiles that changed.
    pub change_ratio: f32,
    /// Why the decision came out this way.
    pub reason: FfiKeepReason,
}

/// Where a text line came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum FfiLineSource {
    /// Read from the pixels by text recognition.
    Ocr,
    /// Read from the focused window's accessibility tree, so the text is exact.
    Accessibility,
    /// The frame's window title. Only the store derives titles, so a line the
    /// app sends with this source is stored as OCR.
    Title,
}

/// One recognized text line with its box on the frame.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiTextLine {
    /// Recognized text.
    pub text: String,
    /// Left edge in `0..=10000`.
    pub x: u16,
    /// Top edge in `0..=10000`.
    pub y: u16,
    /// Width in `0..=10000`.
    pub w: u16,
    /// Height in `0..=10000`.
    pub h: u16,
    /// Where the text came from. The app sends `Ocr` or `Accessibility`; a
    /// `Title` line from the app is stored as `Ocr`, because only the store
    /// derives titles from the frame's window title.
    pub source: FfiLineSource,
}

/// A kept frame ready to be stored.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiNewFrame {
    /// Wall clock capture time in Unix milliseconds.
    pub captured_at_ms: i64,
    /// Database id of the segment holding the frame.
    pub segment_id: i64,
    /// Presentation time inside the segment.
    pub pts_ms: i64,
    /// Bundle identifier of the frontmost app.
    pub bundle_id: String,
    /// Display name of the frontmost app.
    pub app_name: String,
    /// Focused window title, when available.
    pub window_title: Option<String>,
    /// Browser URL, when available.
    pub url: Option<String>,
    /// Fraction of the frame that changed.
    pub change_ratio: f32,
    /// Recognized text lines, empty when OCR was skipped.
    pub lines: Vec<FfiTextLine>,
}

/// The identity and recency of a stored frame.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct FfiFrameStamp {
    /// Frame id.
    pub id: i64,
    /// Capture time in Unix milliseconds.
    pub captured_at_ms: i64,
    /// Fraction of the frame that changed.
    pub change_ratio: f32,
}

/// One moment found by search: consecutive matches of the same app and window.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiSearchHit {
    /// Frame id of the representative frame.
    pub frame_id: i64,
    /// Capture time of the representative frame.
    pub captured_at_ms: i64,
    /// Capture time of the oldest frame in the moment.
    pub first_seen_ms: i64,
    /// Capture time of the newest frame in the moment.
    pub last_seen_ms: i64,
    /// Bundle identifier of the app.
    pub bundle_id: String,
    /// Display name of the app.
    pub app_name: String,
    /// Focused window title, when available.
    pub window_title: Option<String>,
    /// Browser URL, when available.
    pub url: Option<String>,
    /// Absolute path of the segment video, or `None` once retention deleted it.
    pub segment_path: Option<String>,
    /// Presentation time inside the segment.
    pub pts_ms: i64,
    /// Matching lines on the representative frame.
    pub matched_lines: Vec<FfiTextLine>,
}

/// One focus span: an app and window staying on screen.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiSpan {
    /// Span id.
    pub id: i64,
    /// Bundle identifier of the app.
    pub bundle_id: String,
    /// Display name of the app.
    pub app_name: String,
    /// Focused window title, when available.
    pub window_title: Option<String>,
    /// Browser URL, when available.
    pub url: Option<String>,
    /// Start time in Unix milliseconds.
    pub started_at_ms: i64,
    /// End time in Unix milliseconds, `None` while the span is open.
    pub ended_at_ms: Option<i64>,
}

/// Heat, focus spans, and kept frames for one time range.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiTimeline {
    /// Inclusive range start in Unix milliseconds.
    pub start_ms: i64,
    /// Exclusive range end in Unix milliseconds.
    pub end_ms: i64,
    /// Heat levels `0..=5`, one per bucket.
    pub heat: Vec<u8>,
    /// Focus spans overlapping the range.
    pub spans: Vec<FfiSpan>,
    /// Kept frames inside the range.
    pub stamps: Vec<FfiFrameStamp>,
}

/// Everything the moment inspector needs about one frame.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiMoment {
    /// The frame itself.
    pub stamp: FfiFrameStamp,
    /// Bundle identifier of the app.
    pub bundle_id: String,
    /// Display name of the app.
    pub app_name: String,
    /// Focused window title, when available.
    pub window_title: Option<String>,
    /// Browser URL, when available.
    pub url: Option<String>,
    /// Absolute path of the segment video, or `None` once retention deleted it.
    pub segment_path: Option<String>,
    /// Start time of the segment in Unix milliseconds.
    pub segment_started_at_ms: i64,
    /// Presentation time inside the segment.
    pub pts_ms: i64,
    /// Quality tier: 0 full, 1 reduced, 2 text only.
    pub tier: u8,
    /// Every text line read from the frame, ordered top to bottom. The window
    /// title is not one of them: it has no box, and the moment shows it from
    /// `window_title`.
    pub lines: Vec<FfiTextLine>,
    /// Start of the focus span containing the frame.
    pub on_screen_from_ms: Option<i64>,
    /// End of the focus span containing the frame, `None` while it is open.
    pub on_screen_to_ms: Option<i64>,
    /// Today's spans of the same app and window title.
    pub visits_today: u32,
    /// End of the previous span of the same app and window title before today.
    pub last_opened_ms: Option<i64>,
    /// Up to three frames before and three after, in time order.
    pub neighbors: Vec<FfiFrameStamp>,
}

/// A coarse kind of work an activity span represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum FfiCategory {
    /// Writing code, design, or notes.
    Building,
    /// Consuming pages, articles, books, or previews.
    Reading,
    /// Messages, mail, calls, and meetings.
    Talking,
    /// Everything else.
    Other,
}

/// Time spent in one activity category.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FfiCategoryTotal {
    /// Category the time belongs to.
    pub category: FfiCategory,
    /// Clipped milliseconds.
    pub ms: i64,
}

/// The width of one activity bucket.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum FfiBucketKind {
    /// One hour, unaffected by daylight saving.
    Hour,
    /// One local day, from one local midnight to the next.
    Day,
}

/// One bucket of activity, covering `[start_ms, end_ms)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FfiBucket {
    /// Bucket start in Unix milliseconds.
    pub start_ms: i64,
    /// Bucket end in Unix milliseconds, exclusive.
    pub end_ms: i64,
    /// Milliseconds categorized as building.
    pub building_ms: i64,
    /// Milliseconds categorized as reading.
    pub reading_ms: i64,
    /// Milliseconds categorized as talking.
    pub talking_ms: i64,
    /// Milliseconds in the other category.
    pub other_ms: i64,
}

/// Time spent in one app.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiAppTotal {
    /// Bundle identifier of the app.
    pub bundle_id: String,
    /// Display name of the app.
    pub app_name: String,
    /// Clipped milliseconds.
    pub ms: i64,
}

/// Time spent on one website host.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiSiteTotal {
    /// Lowercase host without `www.`.
    pub host: String,
    /// Clipped milliseconds.
    pub ms: i64,
}

/// How a range of time was spent, with the previous range for comparison.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiActivity {
    /// Inclusive range start in Unix milliseconds.
    pub start_ms: i64,
    /// Exclusive range end in Unix milliseconds.
    pub end_ms: i64,
    /// Clipped milliseconds across all spans.
    pub total_ms: i64,
    /// Total of the same-length range right before, `None` when it had no spans.
    pub previous_total_ms: Option<i64>,
    /// Per category totals in enum order.
    pub categories: Vec<FfiCategoryTotal>,
    /// Width of each bucket: one hour, or one local day for a long range.
    pub bucket_kind: FfiBucketKind,
    /// Consecutive buckets covering `[start_ms, end_ms)`, in time order.
    pub buckets: Vec<FfiBucket>,
    /// Per app totals, largest first.
    pub apps: Vec<FfiAppTotal>,
    /// Per website host totals, largest first.
    pub websites: Vec<FfiSiteTotal>,
}

/// Disk usage and history facts for the storage screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FfiStorage {
    /// Video plus database bytes.
    pub used_bytes: u64,
    /// Sum of the recorded size of every segment.
    pub video_bytes: u64,
    /// Main database size as SQLite reports it.
    pub database_bytes: u64,
    /// Stored frames.
    pub frame_count: u64,
    /// Stored segments.
    pub segment_count: u64,
    /// Distinct stored text lines.
    pub unique_line_count: u64,
    /// Capture time of the oldest stored frame.
    pub oldest_ms: Option<i64>,
    /// Capture time of the newest stored frame.
    pub newest_ms: Option<i64>,
    /// Average bytes used per day of recorded history.
    pub average_per_day_bytes: u64,
    /// Bytes of segments started within the last 24 hours.
    pub kept_last_24h_bytes: u64,
    /// Configured storage budget, `None` when unlimited.
    pub limit_bytes: Option<u64>,
}

/// What retention should do with one segment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum FfiRetentionKind {
    /// Re-encode the video at a lower quality.
    Reduce,
    /// Delete the video, keeping text and metadata.
    DeleteVideo,
    /// Delete the video and every frame of the segment, text included.
    DeleteSegment,
}

/// One retention action for a segment.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiRetentionAction {
    /// Segment the action applies to.
    pub segment_id: i64,
    /// What to do with it.
    pub kind: FfiRetentionKind,
    /// Absolute path of the segment video, or `None` when it is already gone.
    pub segment_path: Option<String>,
}

/// What erasing a time range removed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct FfiEraseResult {
    /// Frames deleted, including frames of removed segments outside the range.
    pub frames_removed: u64,
    /// Start of the erased range in Unix milliseconds.
    pub erased_from_ms: i64,
    /// End of the erased range in Unix milliseconds.
    pub erased_to_ms: i64,
    /// `false` while a reader held an old snapshot, so erased text may still be in the write-ahead log.
    pub purge_complete: bool,
}

/// A reminder, optionally anchored to a frame.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiReminder {
    /// Reminder id.
    pub id: i64,
    /// Frame the reminder points at, when it has one.
    pub frame_id: Option<i64>,
    /// Creation time in Unix milliseconds.
    pub created_at_ms: i64,
    /// Time the reminder becomes due.
    pub due_at_ms: i64,
    /// What to remember.
    pub note: String,
    /// Time the reminder was marked done, `None` while it is open.
    pub done_at_ms: Option<i64>,
}

/// One local day of the hourly heat a month view draws.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiDayHeat {
    /// Local midnight in Unix milliseconds, or the range start for the first day.
    pub start_ms: i64,
    /// The next local midnight, or the range end for the last day.
    pub end_ms: i64,
    /// Levels `0..=5` for the 24 wall-clock hours, midnight first.
    pub hours: Vec<u8>,
}

/// The compact numbers the menu bar shows for the current day.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiTodaySummary {
    /// Milliseconds with a span on screen today.
    pub on_screen_ms: i64,
    /// Bytes of segments started today.
    pub kept_bytes: u64,
    /// Heat levels `0..=5`, one per bucket.
    pub heat: Vec<u8>,
    /// Apps with the most time on screen today.
    pub top_apps: Vec<FfiAppTotal>,
}

/// An application identified the same way the capture pipeline identifies it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct FfiAppRef {
    /// Bundle identifier.
    pub bundle_id: String,
    /// Display name.
    pub name: String,
}

/// How much CPU the encoder may spend for smaller files.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum FfiCompression {
    /// Encode quickly.
    Faster,
    /// Encode for smaller files.
    Smaller,
}

/// What happens to a segment once its lighter copy has been made.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum FfiAfterLighterCopy {
    /// Delete the video and keep the text.
    KeepText,
    /// Delete the video with every frame and its text.
    DeleteEverything,
}

/// Everything the capture engine and the retention policy read from settings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
#[serde(default, rename_all = "snake_case")]
pub struct FfiSettings {
    /// Whether capturing is on.
    pub is_recording: bool,
    /// Whether the app starts when the user logs in.
    pub launch_at_login: bool,
    /// Seconds between captured frames, clamped to `1..=10`.
    pub capture_interval_seconds: u32,
    /// Encoder tradeoff.
    pub compression: FfiCompression,
    /// Days a segment keeps its original video.
    pub full_quality_days: u32,
    /// Months the lighter copy is kept, `None` keeps it forever.
    pub lighter_copy_months: Option<u32>,
    /// What happens after the lighter copy period.
    pub after_lighter_copy: FfiAfterLighterCopy,
    /// Storage budget in gigabytes, `None` when unlimited.
    pub storage_limit_gigabytes: Option<u32>,
    /// Apps that are never captured.
    pub excluded_apps: Vec<FfiAppRef>,
    /// How far back agents may read, `None` for all history.
    pub agent_history_days: Option<u32>,
}

/// A segment and the absolute path of its video.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiSegmentVideo {
    pub segment_id: i64,
    pub path: String,
}
