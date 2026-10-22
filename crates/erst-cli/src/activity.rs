//! `erst activity`: time per category, app, and website for one local day.

use std::collections::BTreeMap;
use std::io::Write;

use anyhow::{Context, Result};
use erst_core::activity::{self, ActivitySummary, Category};
use erst_core::time::TimeRange;
use erst_store::{SpanRow, Store};

use crate::cli::ActivityArgs;
use crate::format;

mod json;

/// Apps and websites shown in text output. JSON keeps every entry.
const TOP_APPS: usize = 5;
const TOP_SITES: usize = 5;
const CATEGORY_LABEL_WIDTH: usize = 10;

/// Aggregated activity for one labelled day.
#[derive(Debug)]
pub struct ActivityReport {
    /// The day the user asked for, as `YYYY-MM-DD`.
    pub day: String,
    /// Range that was aggregated, clipped to now and to any agent window.
    pub range: TimeRange,
    pub summary: ActivitySummary,
    /// Bundle id to display name, learned from the spans.
    pub app_names: BTreeMap<String, String>,
}

impl ActivityReport {
    /// Loads spans for `range` and summarizes them. Open spans end at `now_ms`.
    pub fn load(store: &Store, day: &str, range: TimeRange, now_ms: i64) -> Result<Self> {
        let end_ms = range.end_ms.min(now_ms.max(range.start_ms));
        let clipped = TimeRange {
            start_ms: range.start_ms,
            end_ms,
        };
        let spans = store
            .spans_in_range(clipped.start_ms, clipped.end_ms)
            .with_context(|| format!("could not read activity for {day}"))?;
        Self::from_spans(day, clipped, &spans, now_ms)
    }

    fn from_spans(day: &str, range: TimeRange, spans: &[SpanRow], now_ms: i64) -> Result<Self> {
        let mut app_names = BTreeMap::new();
        for span in spans.iter().filter(|span| !span.app_name.is_empty()) {
            app_names
                .entry(span.bundle_id.clone())
                .or_insert_with(|| span.app_name.clone());
        }
        let core_spans: Vec<activity::Span> = spans
            .iter()
            .map(|span| activity::Span {
                bundle_id: span.bundle_id.clone(),
                url: span.url.clone(),
                started_at: span.started_at,
                ended_at: span.ended_at.unwrap_or(now_ms),
            })
            .collect();
        let summary = activity::summarize(&core_spans, range, format::utc_offset_ms)
            .with_context(|| format!("could not summarize activity for {day}"))?;
        Ok(Self {
            day: day.to_owned(),
            range,
            summary,
            app_names,
        })
    }

    /// Display name for a bundle id, falling back to the id itself.
    pub fn app_name<'a>(&'a self, bundle_id: &'a str) -> &'a str {
        self.app_names
            .get(bundle_id)
            .map_or(bundle_id, String::as_str)
    }
}

/// Runs activity for one day and writes the requested format.
pub fn run(store: &Store, args: &ActivityArgs, now_ms: i64, out: &mut impl Write) -> Result<()> {
    let report = report(store, args.day.as_deref(), now_ms)?;
    if args.json {
        json::write(&report, out)
    } else {
        writeln!(out, "{}", summary_text(&report))?;
        Ok(())
    }
}

/// Builds the report for `day`, defaulting to today.
pub fn report(store: &Store, day: Option<&str>, now_ms: i64) -> Result<ActivityReport> {
    let day = match day {
        Some(day) => day.to_owned(),
        None => format::local_date(now_ms).context("could not read the local date")?,
    };
    let range = erst_core::time::local_day_of_text(&day, format::utc_offset_ms)
        .with_context(|| format!("invalid day {day:?}; expected YYYY-MM-DD"))?;
    ActivityReport::load(store, &day, range, now_ms)
}

fn display_name(category: Category) -> &'static str {
    match category {
        Category::Building => "Building",
        Category::Reading => "Reading",
        Category::Talking => "Talking",
        Category::Other => "Other",
    }
}

/// Readable summary shared by the CLI and the MCP `activity_summary` tool.
pub fn summary_text(report: &ActivityReport) -> String {
    let mut lines = vec![format!(
        "{}  total {}",
        report.day,
        format::human_duration(report.summary.total_ms)
    )];
    for (category, ms) in report.summary.categories {
        lines.push(format!(
            "{}{}",
            format::pad_right(display_name(category), CATEGORY_LABEL_WIDTH),
            format::human_duration(ms)
        ));
    }
    append_apps(&mut lines, report);
    append_sites(&mut lines, report);
    lines.join("\n")
}

fn append_apps(lines: &mut Vec<String>, report: &ActivityReport) {
    let apps: Vec<(&str, i64)> = report
        .summary
        .apps
        .iter()
        .take(TOP_APPS)
        .map(|app| (report.app_name(&app.bundle_id), app.ms))
        .collect();
    if apps.is_empty() {
        return;
    }
    let width = apps
        .iter()
        .map(|(name, _)| name.chars().count())
        .max()
        .unwrap_or(0);
    lines.push(String::new());
    lines.push(String::from("Apps"));
    for (name, ms) in apps {
        lines.push(format!(
            "{}{}",
            format::pad_right(name, width + 2),
            format::human_duration(ms)
        ));
    }
}

fn append_sites(lines: &mut Vec<String>, report: &ActivityReport) {
    let sites: Vec<(&str, i64)> = report
        .summary
        .websites
        .iter()
        .take(TOP_SITES)
        .map(|site| (site.host.as_str(), site.ms))
        .collect();
    if sites.is_empty() {
        return;
    }
    let width = sites
        .iter()
        .map(|(host, _)| host.chars().count())
        .max()
        .unwrap_or(0);
    lines.push(String::new());
    lines.push(String::from("Websites"));
    for (host, ms) in sites {
        lines.push(format!(
            "{}{}",
            format::pad_right(host, width + 2),
            format::human_duration(ms)
        ));
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use erst_core::time::{MS_PER_HOUR, TimeRange};
    use erst_store::SpanRow;

    use super::{ActivityReport, summary_text};

    fn span(bundle_id: &str, name: &str, url: Option<&str>, start_hour: i64, ms: i64) -> SpanRow {
        SpanRow {
            id: start_hour,
            bundle_id: String::from(bundle_id),
            app_name: String::from(name),
            window_title: None,
            url: url.map(str::to_owned),
            started_at: start_hour * MS_PER_HOUR,
            ended_at: Some(start_hour * MS_PER_HOUR + ms),
        }
    }

    fn report() -> ActivityReport {
        let spans = vec![
            span("com.apple.dt.Xcode", "Xcode", None, 0, MS_PER_HOUR),
            span(
                "com.apple.Safari",
                "Safari",
                Some("https://example.com/docs"),
                1,
                MS_PER_HOUR / 2,
            ),
            span(
                "com.tinyspeck.slackmacgap",
                "Slack",
                None,
                2,
                MS_PER_HOUR / 4,
            ),
        ];
        ActivityReport::from_spans(
            "2026-10-20",
            TimeRange::new(0, 3 * MS_PER_HOUR).unwrap(),
            &spans,
            3 * MS_PER_HOUR,
        )
        .unwrap()
    }

    #[test]
    fn summary_lists_categories_apps_and_sites() {
        let text = summary_text(&report());
        assert!(text.contains("2026-10-20  total 1h 45m"), "{text}");
        assert!(text.contains("Building  1h"), "{text}");
        assert!(text.contains("Reading   30m"), "{text}");
        assert!(text.contains("Talking   15m"), "{text}");
        assert!(text.contains("Apps"));
        assert!(text.contains("Xcode"));
        assert!(text.contains("Safari"));
        assert!(text.contains("example.com"));
        assert!(!text.contains('\u{1b}'));
    }

    #[test]
    fn unknown_apps_fall_back_to_the_bundle_id() {
        let spans = vec![span("com.example.Unknown", "", None, 0, MS_PER_HOUR)];
        let report = ActivityReport::from_spans(
            "2026-10-20",
            TimeRange::new(0, MS_PER_HOUR).unwrap(),
            &spans,
            MS_PER_HOUR,
        )
        .unwrap();
        assert!(summary_text(&report).contains("com.example.Unknown"));
    }

    #[test]
    fn open_spans_end_at_now() {
        let mut open = span("com.apple.Safari", "Safari", None, 0, 0);
        open.ended_at = None;
        open.started_at = 0;
        let report = ActivityReport::from_spans(
            "2026-10-20",
            TimeRange::new(0, MS_PER_HOUR).unwrap(),
            &[open],
            MS_PER_HOUR / 2,
        )
        .unwrap();
        assert_eq!(report.summary.total_ms, MS_PER_HOUR / 2);
    }

    #[test]
    fn json_is_stable_and_uses_category_slugs() {
        let mut out = Vec::new();
        super::json::write(&report(), &mut out).unwrap();
        let value: serde_json::Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["day"], "2026-10-20");
        assert_eq!(value["total_ms"], 6_300_000);
        assert_eq!(value["categories"][0]["category"], "building");
        assert_eq!(value["categories"][0]["ms"], MS_PER_HOUR);
        assert_eq!(value["apps"][0]["bundle_id"], "com.apple.dt.Xcode");
        assert_eq!(value["websites"][0]["host"], "example.com");
    }
}
