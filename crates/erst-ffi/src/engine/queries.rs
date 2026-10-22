//! Read paths: search, timeline, moments, activity, storage, and today.
//!
//! Every call that reads a local day takes the zone name the app runs in. The
//! zone resolves local midnight at the right instant, including on a daylight
//! saving day.

use erst_core::{
    MS_PER_DAY, TimeRange, heat_buckets, hourly_heat, local_day_containing, now_ms, summarize,
};
use erst_store::{SearchParams, SpanRow};

use super::{Engine, checked_range};
use crate::convert;
use crate::error::ErstError;
use crate::records::{
    FfiActivity, FfiAppTotal, FfiDayHeat, FfiFrameStamp, FfiMoment, FfiSearchHit, FfiStorage,
    FfiTimeline, FfiTodaySummary,
};
use crate::settings::BYTES_PER_GIGABYTE;
use crate::zone::Zone;

/// Frames shown before the focused one in the moment inspector.
const NEIGHBORS_BEFORE: u32 = 3;
/// Frames shown after the focused one in the moment inspector.
const NEIGHBORS_AFTER: u32 = 3;
/// Apps listed in the menu bar summary.
const TODAY_TOP_APPS: usize = 3;

#[uniffi::export]
impl Engine {
    /// Searches stored text and returns moments, most recent first.
    ///
    /// `time_zone` is an IANA name such as `America/New_York` and anchors
    /// `today`, `yesterday`, and the date filters. A query with no FTS terms
    /// (for example only `app:Safari`) returns no hits.
    pub fn search(
        &self,
        query: String,
        limit: u32,
        time_zone: String,
    ) -> Result<Vec<FfiSearchHit>, ErstError> {
        let zone = Zone::named(&time_zone)?;
        let parsed = erst_core::parse(&query, now_ms(), |at| zone.offset_ms_at(at));
        let Some(fts_match) = parsed.fts_match() else {
            return Ok(Vec::new());
        };
        let params = SearchParams {
            fts_match,
            app: parsed.app,
            since_ms: parsed.since_ms,
            until_ms: parsed.until_ms,
            limit,
        };
        Ok(self
            .store
            .search(&params)?
            .into_iter()
            .map(|hit| convert::search_hit(self.data_dir(), hit))
            .collect())
    }

    /// Heat, focus spans, and kept frames for `[start_ms, end_ms)`.
    pub fn timeline(
        &self,
        start_ms: i64,
        end_ms: i64,
        buckets: u32,
    ) -> Result<FfiTimeline, ErstError> {
        let range = checked_range(start_ms, end_ms)?;
        let frames = self.store.frames_in_range(range.start_ms, range.end_ms)?;
        let spans = self.store.spans_in_range(range.start_ms, range.end_ms)?;
        let stamps: Vec<(i64, f32)> = frames
            .iter()
            .map(|frame| (frame.captured_at, frame.change_ratio))
            .collect();
        let heat = heat_buckets(
            &stamps,
            range,
            usize::try_from(buckets).unwrap_or(usize::MAX),
        )?;
        Ok(FfiTimeline {
            start_ms,
            end_ms,
            heat,
            spans: spans.into_iter().map(convert::span).collect(),
            stamps: frames.into_iter().map(convert::stamp).collect(),
        })
    }

    /// Heat for every wall-clock hour of the local days in `[start_ms, end_ms)`,
    /// levelled against the busiest hour of the range so the days compare.
    ///
    /// `time_zone` is an IANA name. Start the range at a local midnight for
    /// whole days. A range longer than about 170 days is `InvalidInput`.
    pub fn hourly_heat(
        &self,
        start_ms: i64,
        end_ms: i64,
        time_zone: String,
    ) -> Result<Vec<FfiDayHeat>, ErstError> {
        let zone = Zone::named(&time_zone)?;
        let range = checked_range(start_ms, end_ms)?;
        let stamps: Vec<(i64, f32)> = self
            .store
            .frames_in_range(range.start_ms, range.end_ms)?
            .iter()
            .map(|frame| (frame.captured_at, frame.change_ratio))
            .collect();
        Ok(hourly_heat(&stamps, range, |at| zone.offset_ms_at(at))?
            .into_iter()
            .map(|day| FfiDayHeat {
                start_ms: day.day.start_ms,
                end_ms: day.day.end_ms,
                hours: day.hours.to_vec(),
            })
            .collect())
    }

    /// Everything the inspector shows for one frame, including its neighbors
    /// and how often the same app and window appeared today.
    ///
    /// `time_zone` anchors "today" for the visit counts.
    pub fn moment(&self, frame_id: i64, time_zone: String) -> Result<FfiMoment, ErstError> {
        let zone = Zone::named(&time_zone)?;
        let detail = self.store.frame_detail(frame_id)?;
        let containing = self.containing_span(detail.stamp.captured_at)?;
        let window_title = detail.window_title.as_deref();

        let clock = now_ms();
        let midnight = local_day_containing(clock, |at| zone.offset_ms_at(at)).start_ms;
        let today = self
            .store
            .spans_in_range(midnight, clock.saturating_add(1))?;
        let visits_today = today
            .iter()
            .filter(|span| span.started_at >= midnight)
            .filter(|span| is_same_window(span, &detail.bundle_id, window_title))
            .count();

        let last_opened_ms = self
            .store
            .last_span_before(&detail.bundle_id, window_title, midnight)?
            .and_then(|span| span.ended_at);

        let neighbors = self
            .store
            .neighbors(frame_id, NEIGHBORS_BEFORE, NEIGHBORS_AFTER)?;

        Ok(FfiMoment {
            stamp: convert::stamp(detail.stamp),
            bundle_id: detail.bundle_id,
            app_name: detail.app_name,
            window_title: detail.window_title,
            url: detail.url,
            segment_path: convert::absolute_path(self.data_dir(), detail.segment_path.as_deref()),
            segment_started_at_ms: detail.segment_started_at,
            pts_ms: detail.pts_ms,
            tier: detail.tier,
            lines: detail.lines.into_iter().map(convert::line).collect(),
            on_screen_from_ms: containing.as_ref().map(|span| span.started_at),
            on_screen_to_ms: containing.as_ref().and_then(|span| span.ended_at),
            visits_today: u32::try_from(visits_today).unwrap_or(u32::MAX),
            last_opened_ms,
            neighbors: neighbors.into_iter().map(convert::stamp).collect(),
        })
    }

    /// The frame closest in time to `at_ms`, earlier on a tie.
    pub fn nearest_moment(&self, at_ms: i64) -> Result<Option<FfiFrameStamp>, ErstError> {
        Ok(self.store.nearest_frame(at_ms)?.map(convert::stamp))
    }

    /// How `[start_ms, end_ms)` was spent, with the same-length range before it.
    ///
    /// `time_zone` is an IANA name. Buckets are hours for a range of up to three
    /// days and local days after that, each day starting at its own local
    /// midnight, so a daylight saving day is 23 or 25 hours long. A range that
    /// needs more buckets than the limit is an invalid input error.
    pub fn activity(
        &self,
        start_ms: i64,
        end_ms: i64,
        time_zone: String,
    ) -> Result<FfiActivity, ErstError> {
        let zone = Zone::named(&time_zone)?;
        let range = checked_range(start_ms, end_ms)?;
        let clock = now_ms();
        let rows = self.store.spans_in_range(range.start_ms, range.end_ms)?;
        let names = convert::app_names(&rows);
        let summary = summarize(&convert::core_spans(&rows, clock), range, |at| {
            zone.offset_ms_at(at)
        })?;

        let previous_range = TimeRange {
            start_ms: range.start_ms.saturating_sub(range.duration_ms()),
            end_ms: range.start_ms,
        };
        let previous_rows = self
            .store
            .spans_in_range(previous_range.start_ms, previous_range.end_ms)?;
        let previous_total_ms = if previous_rows.is_empty() {
            None
        } else {
            Some(
                summarize(
                    &convert::core_spans(&previous_rows, clock),
                    previous_range,
                    |at| zone.offset_ms_at(at),
                )?
                .total_ms,
            )
        };

        let categories = summary
            .categories
            .iter()
            .map(|total| convert::category_total(*total))
            .collect();
        let bucket_kind = convert::bucket_kind(summary.kind);
        let buckets = summary.buckets.into_iter().map(convert::bucket).collect();
        let apps = summary
            .apps
            .into_iter()
            .map(|app| {
                let app_name = convert::app_name(&names, &app.bundle_id);
                FfiAppTotal {
                    bundle_id: app.bundle_id,
                    app_name,
                    ms: app.ms,
                }
            })
            .collect();
        let websites = summary
            .websites
            .into_iter()
            .map(convert::site_total)
            .collect();

        Ok(FfiActivity {
            start_ms,
            end_ms,
            total_ms: summary.total_ms,
            previous_total_ms,
            categories,
            bucket_kind,
            buckets,
            apps,
            websites,
        })
    }

    /// Disk usage and history facts for the storage screen.
    pub fn storage(&self) -> Result<FfiStorage, ErstError> {
        let clock = now_ms();
        let stats = self.store.storage_stats(clock)?;
        let settings = self.load_settings()?;
        let used_bytes = stats.video_bytes.saturating_add(stats.database_bytes);
        let limit_bytes = settings
            .storage_limit_gigabytes
            .map(|gigabytes| u64::from(gigabytes).saturating_mul(BYTES_PER_GIGABYTE));
        Ok(FfiStorage {
            used_bytes,
            video_bytes: stats.video_bytes,
            database_bytes: stats.database_bytes,
            frame_count: stats.frame_count,
            segment_count: stats.segment_count,
            unique_line_count: stats.unique_line_count,
            oldest_ms: stats.oldest_ms,
            newest_ms: stats.newest_ms,
            average_per_day_bytes: average_per_day_bytes(used_bytes, stats.oldest_ms, clock),
            kept_last_24h_bytes: stats.video_bytes_last_24h,
            limit_bytes,
        })
    }

    /// The compact numbers the menu bar shows for the current local day.
    ///
    /// `time_zone` is an IANA name. The day starts at its local midnight at
    /// `now_ms`, so a daylight saving day starts at the right instant.
    pub fn today_summary(
        &self,
        now_ms: i64,
        time_zone: String,
        buckets: u32,
    ) -> Result<FfiTodaySummary, ErstError> {
        let zone = Zone::named(&time_zone)?;
        let midnight = local_day_containing(now_ms, |at| zone.offset_ms_at(at)).start_ms;
        let frame_end_ms = now_ms.saturating_add(1).max(midnight.saturating_add(1));
        let frames = self.store.frames_in_range(midnight, frame_end_ms)?;
        let span_rows = self.store.spans_in_range(midnight, frame_end_ms)?;
        let names = convert::app_names(&span_rows);
        let range = TimeRange {
            start_ms: midnight,
            end_ms: now_ms.max(midnight),
        };
        let summary = summarize(&convert::core_spans(&span_rows, now_ms), range, |at| {
            zone.offset_ms_at(at)
        })?;

        let stamps: Vec<(i64, f32)> = frames
            .iter()
            .map(|frame| (frame.captured_at, frame.change_ratio))
            .collect();
        let heat = heat_buckets(
            &stamps,
            TimeRange {
                start_ms: midnight,
                end_ms: frame_end_ms,
            },
            usize::try_from(buckets).unwrap_or(usize::MAX),
        )?;
        let kept_bytes = self
            .store
            .segments()?
            .iter()
            .filter(|segment| segment.started_at >= midnight && segment.started_at <= now_ms)
            .fold(0_u64, |total, segment| total.saturating_add(segment.bytes));
        let on_screen_ms = summary.total_ms;
        let top_apps = summary
            .apps
            .into_iter()
            .take(TODAY_TOP_APPS)
            .map(|app| {
                let app_name = convert::app_name(&names, &app.bundle_id);
                FfiAppTotal {
                    bundle_id: app.bundle_id,
                    app_name,
                    ms: app.ms,
                }
            })
            .collect();

        Ok(FfiTodaySummary {
            on_screen_ms,
            kept_bytes,
            heat,
            top_apps,
        })
    }
}

impl Engine {
    /// The most recent span covering `at_ms`, if any.
    fn containing_span(&self, at_ms: i64) -> Result<Option<SpanRow>, ErstError> {
        let spans = self.store.spans_in_range(at_ms, at_ms.saturating_add(1))?;
        Ok(spans
            .into_iter()
            .filter(|span| span.started_at <= at_ms && span.ended_at.is_none_or(|end| end > at_ms))
            .max_by_key(|span| span.started_at))
    }
}

fn is_same_window(span: &SpanRow, bundle_id: &str, window_title: Option<&str>) -> bool {
    span.bundle_id == bundle_id && span.window_title.as_deref() == window_title
}

/// Average bytes used per day of recorded history, at least one day.
fn average_per_day_bytes(used_bytes: u64, oldest_ms: Option<i64>, now_ms: i64) -> u64 {
    let Some(oldest_ms) = oldest_ms else {
        return 0;
    };
    let history_ms = now_ms.saturating_sub(oldest_ms).max(0);
    let days = u64::try_from(history_ms / MS_PER_DAY).unwrap_or(0).max(1);
    used_bytes / days
}
