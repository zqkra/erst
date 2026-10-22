//! Shared helpers for the store integration tests.

#![allow(dead_code)]

use std::error::Error;

use erst_store::{LineSource, NewFrame, NewLine, SearchParams, Store};
use tempfile::TempDir;

pub const APP: &str = "com.example.App";
pub const APP_NAME: &str = "Example";
pub const TITLE: &str = "Window";

/// Test errors must cross thread boundaries in the concurrency test.
pub type TestResult = Result<(), Box<dyn Error + Send + Sync>>;

pub fn open_store() -> Result<(TempDir, Store), Box<dyn Error + Send + Sync>> {
    let dir = tempfile::tempdir()?;
    let store = Store::open(&dir.path().join("erst.sqlite"))?;
    Ok((dir, store))
}

pub fn begin_segment(store: &Store) -> Result<i64, Box<dyn Error + Send + Sync>> {
    Ok(store.begin_segment("segments/2026/10/20/120000-1.mp4", 0, 1920, 1080)?)
}

pub fn line(text: &str, index: u16) -> NewLine {
    NewLine {
        text: text.to_owned(),
        x: 100,
        y: 100 + index * 200,
        w: 1_000,
        h: 100,
        source: LineSource::Ocr,
    }
}

pub fn frame(
    segment_id: i64,
    captured_at: i64,
    bundle_id: &str,
    app_name: &str,
    window_title: Option<&str>,
    lines: Vec<NewLine>,
) -> NewFrame {
    NewFrame {
        captured_at,
        segment_id,
        pts_ms: 0,
        bundle_id: bundle_id.to_owned(),
        app_name: app_name.to_owned(),
        window_title: window_title.map(str::to_owned),
        url: None,
        change_ratio: 0.01,
        lines,
    }
}

pub fn simple_frame(segment_id: i64, captured_at: i64, lines: &[&str]) -> NewFrame {
    let lines = lines
        .iter()
        .enumerate()
        .map(|(index, text)| line(text, u16::try_from(index).unwrap_or(0)))
        .collect();
    frame(segment_id, captured_at, APP, APP_NAME, Some(TITLE), lines)
}

pub fn search_params(fts_match: &str, limit: u32) -> SearchParams {
    SearchParams {
        fts_match: fts_match.to_owned(),
        app: None,
        since_ms: None,
        until_ms: None,
        limit,
    }
}
