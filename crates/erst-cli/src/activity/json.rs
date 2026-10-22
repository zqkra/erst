//! JSON shape of `erst activity --json`.

use std::io::Write;

use anyhow::Result;
use erst_core::activity::Category;
use serde::Serialize;

use super::ActivityReport;

fn slug(category: Category) -> &'static str {
    match category {
        Category::Building => "building",
        Category::Reading => "reading",
        Category::Talking => "talking",
        Category::Other => "other",
    }
}

#[derive(Debug, Serialize)]
struct JsonCategory {
    category: &'static str,
    ms: i64,
}

#[derive(Debug, Serialize)]
struct JsonApp<'a> {
    bundle_id: &'a str,
    name: &'a str,
    ms: i64,
}

#[derive(Debug, Serialize)]
struct JsonSite<'a> {
    host: &'a str,
    ms: i64,
}

#[derive(Debug, Serialize)]
struct JsonActivity<'a> {
    day: &'a str,
    start_ms: i64,
    end_ms: i64,
    total_ms: i64,
    categories: Vec<JsonCategory>,
    apps: Vec<JsonApp<'a>>,
    websites: Vec<JsonSite<'a>>,
}

fn snapshot(report: &ActivityReport) -> JsonActivity<'_> {
    JsonActivity {
        day: &report.day,
        start_ms: report.range.start_ms,
        end_ms: report.range.end_ms,
        total_ms: report.summary.total_ms,
        categories: report
            .summary
            .categories
            .iter()
            .map(|(category, ms)| JsonCategory {
                category: slug(*category),
                ms: *ms,
            })
            .collect(),
        apps: report
            .summary
            .apps
            .iter()
            .map(|app| JsonApp {
                bundle_id: &app.bundle_id,
                name: report.app_name(&app.bundle_id),
                ms: app.ms,
            })
            .collect(),
        websites: report
            .summary
            .websites
            .iter()
            .map(|site| JsonSite {
                host: &site.host,
                ms: site.ms,
            })
            .collect(),
    }
}

pub fn write(report: &ActivityReport, out: &mut impl Write) -> Result<()> {
    serde_json::to_writer_pretty(&mut *out, &snapshot(report))?;
    writeln!(out)?;
    Ok(())
}
