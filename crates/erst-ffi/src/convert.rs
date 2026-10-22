//! Mapping between crate types and the FFI records.
//!
//! The FFI layer owns the shapes Swift sees; this module is the only place that
//! knows how those shapes line up with `erst-core` and `erst-store`.

use std::collections::HashMap;
use std::path::Path;

use erst_core::{
    ActivityBucket, AfterLighterCopy, Category, KeepDecision, KeepReason, SegmentInfo, Thumbnail,
    Tier,
};
use erst_store::{
    FrameStamp, LineBox, LineSource, NewFrame as StoreFrame, NewLine, ReminderRow, SearchHit,
    SegmentRow, SpanRow,
};

use crate::error::ErstError;
use crate::records::{
    FfiAfterLighterCopy, FfiBucket, FfiBucketKind, FfiCategory, FfiCategoryTotal, FfiFrameStamp,
    FfiKeepDecision, FfiKeepReason, FfiLineSource, FfiNewFrame, FfiReminder, FfiRetentionKind,
    FfiSearchHit, FfiSiteTotal, FfiSpan, FfiTextLine, FfiThumbnail,
};

/// Validates a thumbnail and converts it to the core type.
///
/// # Errors
///
/// Returns [`ErstError::InvalidInput`] when the dimensions and buffer disagree.
pub(crate) fn thumbnail(value: FfiThumbnail) -> Result<Thumbnail, ErstError> {
    Ok(Thumbnail::new(value.width, value.height, value.luma)?)
}

/// Maps a keep decision to its record.
pub(crate) fn keep_decision(value: KeepDecision) -> FfiKeepDecision {
    FfiKeepDecision {
        keep: value.keep,
        change_ratio: value.change_ratio,
        reason: keep_reason(value.reason),
    }
}

fn keep_reason(value: KeepReason) -> FfiKeepReason {
    match value {
        KeepReason::Changed => FfiKeepReason::Changed,
        KeepReason::FocusChanged => FfiKeepReason::FocusChanged,
        KeepReason::MaxGap => FfiKeepReason::MaxGap,
        KeepReason::FirstFrame => FfiKeepReason::FirstFrame,
        KeepReason::Unchanged => FfiKeepReason::Unchanged,
        KeepReason::MajorChanged => FfiKeepReason::MajorChanged,
        KeepReason::MinorDeferred => FfiKeepReason::MinorDeferred,
        KeepReason::MotionThrottled => FfiKeepReason::MotionThrottled,
    }
}

/// Maps a stored text line to its record.
pub(crate) fn line(value: LineBox) -> FfiTextLine {
    FfiTextLine {
        text: value.text,
        x: value.x,
        y: value.y,
        w: value.w,
        h: value.h,
        source: line_source(value.source),
    }
}

fn line_source(value: LineSource) -> FfiLineSource {
    match value {
        LineSource::Ocr => FfiLineSource::Ocr,
        LineSource::Accessibility => FfiLineSource::Accessibility,
        LineSource::Title => FfiLineSource::Title,
    }
}

/// A line the app sends is OCR or accessibility text. The store derives titles
/// from the frame's window title, so a `Title` from the app is stored as OCR.
fn store_line_source(value: FfiLineSource) -> LineSource {
    match value {
        FfiLineSource::Ocr | FfiLineSource::Title => LineSource::Ocr,
        FfiLineSource::Accessibility => LineSource::Accessibility,
    }
}

fn store_line(value: &FfiTextLine) -> NewLine {
    NewLine {
        text: value.text.clone(),
        x: value.x,
        y: value.y,
        w: value.w,
        h: value.h,
        source: store_line_source(value.source),
    }
}

/// Maps a new frame to the store type.
pub(crate) fn new_frame(value: FfiNewFrame) -> StoreFrame {
    StoreFrame {
        captured_at: value.captured_at_ms,
        segment_id: value.segment_id,
        pts_ms: value.pts_ms,
        bundle_id: value.bundle_id,
        app_name: value.app_name,
        window_title: value.window_title,
        url: value.url,
        change_ratio: value.change_ratio,
        lines: value.lines.iter().map(store_line).collect(),
    }
}

/// Maps a frame stamp to its record.
pub(crate) fn stamp(value: FrameStamp) -> FfiFrameStamp {
    FfiFrameStamp {
        id: value.id,
        captured_at_ms: value.captured_at,
        change_ratio: value.change_ratio,
    }
}

/// Maps a stored search hit to its record, resolving the segment path against
/// the data directory.
pub(crate) fn search_hit(data_dir: &Path, value: SearchHit) -> FfiSearchHit {
    FfiSearchHit {
        frame_id: value.frame_id,
        captured_at_ms: value.captured_at,
        first_seen_ms: value.first_seen_ms,
        last_seen_ms: value.last_seen_ms,
        bundle_id: value.bundle_id,
        app_name: value.app_name,
        window_title: value.window_title,
        url: value.url,
        segment_path: absolute_path(data_dir, value.segment_path.as_deref()),
        pts_ms: value.pts_ms,
        matched_lines: value.matched_lines.into_iter().map(line).collect(),
    }
}

/// Maps a stored span to its record.
pub(crate) fn span(value: SpanRow) -> FfiSpan {
    FfiSpan {
        id: value.id,
        bundle_id: value.bundle_id,
        app_name: value.app_name,
        window_title: value.window_title,
        url: value.url,
        started_at_ms: value.started_at,
        ended_at_ms: value.ended_at,
    }
}

/// Turns stored spans into core spans, closing open ones at `open_end_ms`.
pub(crate) fn core_spans(rows: &[SpanRow], open_end_ms: i64) -> Vec<erst_core::Span> {
    rows.iter()
        .map(|row| erst_core::Span {
            bundle_id: row.bundle_id.clone(),
            url: row.url.clone(),
            started_at: row.started_at,
            ended_at: row.ended_at.unwrap_or(open_end_ms),
        })
        .collect()
}

/// Display names keyed by bundle identifier, taken from stored spans.
pub(crate) fn app_names(rows: &[SpanRow]) -> HashMap<String, String> {
    rows.iter()
        .map(|row| (row.bundle_id.clone(), row.app_name.clone()))
        .collect()
}

/// The display name for a bundle identifier, falling back to the identifier.
pub(crate) fn app_name(names: &HashMap<String, String>, bundle_id: &str) -> String {
    names
        .get(bundle_id)
        .cloned()
        .unwrap_or_else(|| bundle_id.to_owned())
}

/// Maps a stored quality tier to the core tier.
pub(crate) fn tier(value: u8) -> Tier {
    match value {
        0 => Tier::Full,
        1 => Tier::Reduced,
        _ => Tier::TextOnly,
    }
}

/// Converts a stored segment row to the core retention view.
pub(crate) fn segment_info(value: &SegmentRow) -> SegmentInfo {
    SegmentInfo {
        id: value.id,
        started_at: value.started_at,
        bytes: value.bytes,
        tier: tier(value.tier),
    }
}

/// Maps a core retention kind to its record.
pub(crate) fn retention_kind(value: erst_core::RetentionKind) -> FfiRetentionKind {
    match value {
        erst_core::RetentionKind::Reduce => FfiRetentionKind::Reduce,
        erst_core::RetentionKind::DeleteVideo => FfiRetentionKind::DeleteVideo,
        erst_core::RetentionKind::DeleteSegment => FfiRetentionKind::DeleteSegment,
    }
}

/// Maps the stored lighter copy choice to the core policy.
pub(crate) fn after_lighter_copy(value: FfiAfterLighterCopy) -> AfterLighterCopy {
    match value {
        FfiAfterLighterCopy::KeepText => AfterLighterCopy::KeepText,
        FfiAfterLighterCopy::DeleteEverything => AfterLighterCopy::DeleteEverything,
    }
}

/// Maps a core activity category to its record.
pub(crate) fn category(value: Category) -> FfiCategory {
    match value {
        Category::Building => FfiCategory::Building,
        Category::Reading => FfiCategory::Reading,
        Category::Talking => FfiCategory::Talking,
        Category::Other => FfiCategory::Other,
    }
}

/// Maps one core activity bucket to its record.
pub(crate) fn bucket(value: ActivityBucket) -> FfiBucket {
    FfiBucket {
        start_ms: value.start_ms,
        end_ms: value.end_ms,
        building_ms: value.building_ms,
        reading_ms: value.reading_ms,
        talking_ms: value.talking_ms,
        other_ms: value.other_ms,
    }
}

/// Maps the core bucket kind to its record.
pub(crate) fn bucket_kind(value: erst_core::BucketKind) -> FfiBucketKind {
    match value {
        erst_core::BucketKind::Hour => FfiBucketKind::Hour,
        erst_core::BucketKind::Day => FfiBucketKind::Day,
    }
}

/// Maps one core category total to its record.
pub(crate) fn category_total(value: (Category, i64)) -> FfiCategoryTotal {
    FfiCategoryTotal {
        category: category(value.0),
        ms: value.1,
    }
}

/// Maps one core website total to its record.
pub(crate) fn site_total(value: erst_core::SiteTotal) -> FfiSiteTotal {
    FfiSiteTotal {
        host: value.host,
        ms: value.ms,
    }
}

/// Maps a stored reminder to its record.
pub(crate) fn reminder(value: ReminderRow) -> FfiReminder {
    FfiReminder {
        id: value.id,
        frame_id: value.frame_id,
        created_at_ms: value.created_at,
        due_at_ms: value.due_at,
        note: value.note,
        done_at_ms: value.done_at,
    }
}

/// Resolves a stored relative path against the data directory.
///
/// Absolute paths are returned unchanged, which keeps old databases usable if
/// they ever stored one.
pub(crate) fn absolute_path(data_dir: &Path, relative: Option<&str>) -> Option<String> {
    relative.map(|relative| {
        let path = Path::new(relative);
        let absolute = if path.is_absolute() {
            path.to_path_buf()
        } else {
            data_dir.join(path)
        };
        absolute.to_string_lossy().into_owned()
    })
}
