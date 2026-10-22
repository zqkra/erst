//! `erst search`: full-text search over stored moments.

use std::io::Write;

use anyhow::{Context, Result, bail};
use erst_core::query;
use erst_store::{SearchHit, SearchParams, Store};
use serde::Serialize;

use crate::cli::SearchArgs;
use crate::format;
use crate::window::{self, HistoryWindow};

/// Runs a search inside the agent history window and writes the requested format.
pub fn run(store: &Store, args: &SearchArgs, now_ms: i64, out: &mut impl Write) -> Result<()> {
    let history = window::history_window(store)?;
    let hits = execute(store, args, history, now_ms)?;
    if let Some(note) = history.note() {
        eprintln!("{note}");
    }
    if args.json {
        write_json(&hits, out)
    } else {
        write_text(&hits, out)
    }
}

/// Parses the query with local day boundaries and runs it against the store, never reaching
/// past `history`.
pub fn execute(
    store: &Store,
    args: &SearchArgs,
    history: HistoryWindow,
    now_ms: i64,
) -> Result<Vec<SearchHit>> {
    let input = args.query.join(" ");
    let parsed = query::parse(&input, now_ms, format::utc_offset_ms);
    let Some(fts_match) = parsed.fts_match() else {
        bail!("nothing to search for; add a word or a phrase to the query");
    };
    let params = SearchParams {
        fts_match,
        app: parsed.app,
        since_ms: history.clamp_since(parsed.since_ms, now_ms),
        until_ms: parsed.until_ms,
        limit: args.limit,
    };
    store
        .search(&params)
        .with_context(|| format!("could not search for {input:?}"))
}

/// One moment as JSON. Strings stay ISO 8601 so consumers never guess a format.
#[derive(Debug, Serialize)]
struct JsonHit {
    frame_id: i64,
    captured_at: i64,
    time: String,
    first_seen_ms: i64,
    last_seen_ms: i64,
    bundle_id: String,
    app: String,
    window_title: Option<String>,
    url: Option<String>,
    segment_path: Option<String>,
    pts_ms: i64,
    matched_lines: Vec<String>,
}

impl JsonHit {
    fn new(hit: &SearchHit) -> Self {
        Self {
            frame_id: hit.frame_id,
            captured_at: hit.captured_at,
            time: format::iso_local(hit.captured_at),
            first_seen_ms: hit.first_seen_ms,
            last_seen_ms: hit.last_seen_ms,
            bundle_id: hit.bundle_id.clone(),
            app: hit.app_name.clone(),
            window_title: hit.window_title.clone(),
            url: hit.url.clone(),
            segment_path: hit.segment_path.clone(),
            pts_ms: hit.pts_ms,
            matched_lines: hit
                .matched_lines
                .iter()
                .map(|line| line.text.clone())
                .collect(),
        }
    }
}

fn write_json(hits: &[SearchHit], out: &mut impl Write) -> Result<()> {
    let json: Vec<JsonHit> = hits.iter().map(JsonHit::new).collect();
    serde_json::to_writer_pretty(&mut *out, &json)?;
    writeln!(out)?;
    Ok(())
}

fn write_text(hits: &[SearchHit], out: &mut impl Write) -> Result<()> {
    if hits.is_empty() {
        writeln!(out, "no moments matched")?;
        return Ok(());
    }
    let app_width = hits
        .iter()
        .map(|hit| hit.app_name.chars().count())
        .max()
        .unwrap_or(0);
    for (index, hit) in hits.iter().enumerate() {
        if index > 0 {
            writeln!(out)?;
        }
        write_moment(hit, app_width, out)?;
    }
    Ok(())
}

fn write_moment(hit: &SearchHit, app_width: usize, out: &mut impl Write) -> Result<()> {
    let time = format::local_time(hit.captured_at);
    match hit
        .window_title
        .as_deref()
        .filter(|title| !title.is_empty())
    {
        Some(title) => writeln!(
            out,
            "{} {}  {}  {}",
            format::local_date(hit.captured_at).unwrap_or_default(),
            time,
            format::pad_right(&hit.app_name, app_width),
            title
        )?,
        None => writeln!(
            out,
            "{} {}  {}",
            format::local_date(hit.captured_at).unwrap_or_default(),
            time,
            hit.app_name
        )?,
    }
    if let Some(url) = hit.url.as_deref().filter(|url| !url.is_empty()) {
        writeln!(out, "  {url}")?;
    }
    for line in &hit.matched_lines {
        writeln!(out, "  {}", line.text.trim())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use erst_store::{LineBox, LineSource, SearchHit};

    use super::{write_json, write_text};

    fn hit(app: &str, title: Option<&str>, lines: &[&str]) -> SearchHit {
        SearchHit {
            frame_id: 7,
            captured_at: 1_792_029_600_000,
            first_seen_ms: 1_792_029_600_000,
            last_seen_ms: 1_792_029_600_000,
            bundle_id: String::from("com.example.App"),
            app_name: String::from(app),
            window_title: title.map(str::to_owned),
            url: Some(String::from("https://example.com/")),
            segment_path: Some(String::from("segments/1.mp4")),
            pts_ms: 0,
            matched_lines: lines
                .iter()
                .map(|text| LineBox {
                    text: String::from(*text),
                    x: 0,
                    y: 0,
                    w: 0,
                    h: 0,
                    source: LineSource::Ocr,
                })
                .collect(),
        }
    }

    #[test]
    fn text_output_names_time_app_title_url_and_matched_text() {
        let hits = vec![
            hit("Safari", Some("Docs"), &["the zebra crossing"]),
            hit("Notes", None, &["zebra reminder"]),
        ];
        let mut out = Vec::new();
        write_text(&hits, &mut out).unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("Safari"));
        assert!(text.contains("Docs"));
        assert!(text.contains("https://example.com/"));
        assert!(text.contains("the zebra crossing"));
        assert!(text.contains("zebra reminder"));
        assert!(!text.contains('\u{1b}'));
        // Both app names share one column even when only one has a title.
        let safari_line = text.lines().next().unwrap();
        assert!(safari_line.contains("Safari  Docs"));
    }

    #[test]
    fn empty_text_output_says_so() {
        let mut out = Vec::new();
        write_text(&[], &mut out).unwrap();
        assert_eq!(String::from_utf8(out).unwrap(), "no moments matched\n");
    }

    #[test]
    fn json_output_is_an_array_with_stable_keys() {
        let hits = vec![hit("Safari", Some("Docs"), &["the zebra crossing"])];
        let mut out = Vec::new();
        write_json(&hits, &mut out).unwrap();
        let parsed: serde_json::Value = serde_json::from_slice(&out).unwrap();
        let moment = &parsed[0];
        assert_eq!(moment["frame_id"], 7);
        assert_eq!(moment["app"], "Safari");
        assert_eq!(moment["window_title"], "Docs");
        assert_eq!(moment["matched_lines"][0], "the zebra crossing");
        assert!(moment["time"].as_str().unwrap().contains('T'));
    }
}
