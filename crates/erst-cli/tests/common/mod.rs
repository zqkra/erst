//! Shared fixture for the binary integration tests.

#![allow(dead_code, clippy::unwrap_used, clippy::expect_used)]

use std::path::Path;
use std::process::{Command, Output};
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::{DateTime, Local, Offset, Utc};
use erst_core::time::{MS_PER_DAY, MS_PER_HOUR, local_day_containing};
use erst_store::{LineSource, NewFrame, NewLine, Store};
use tempfile::TempDir;

pub const APP_BUNDLE: &str = "com.example.App";
pub const APP_NAME: &str = "Example";
pub const OTHER_BUNDLE: &str = "com.example.Other";
pub const OTHER_NAME: &str = "Other App";
pub const VIDEO_BYTES: u64 = 5 * 1024 * 1024;

/// Ids and facts the tests assert against.
#[derive(Debug, Clone)]
pub struct Seed {
    pub other_frame_id: i64,
    pub ordered_frame_id: i64,
    pub old_frame_id: Option<i64>,
    pub activity_day: String,
    pub old_day: Option<String>,
}

pub struct Fixture {
    pub dir: TempDir,
    pub seed: Seed,
}

pub fn now_ms() -> i64 {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before the epoch");
    i64::try_from(elapsed.as_millis()).expect("clock fits in i64")
}

fn local_date_of(at_ms: i64) -> String {
    DateTime::<Utc>::from_timestamp_millis(at_ms)
        .expect("timestamp in range")
        .with_timezone(&Local)
        .format("%Y-%m-%d")
        .to_string()
}

fn local_offset_ms(at_ms: i64) -> i64 {
    let seconds = DateTime::<Utc>::from_timestamp_millis(at_ms)
        .expect("timestamp in range")
        .with_timezone(&Local)
        .offset()
        .fix()
        .local_minus_utc();
    i64::from(seconds) * 1_000
}

/// The standard fixture: one segment, four frames, two spans, no settings.
pub fn fixture() -> Fixture {
    fixture_with(None, false)
}

/// A fixture with an optional `settings.v1` value and optional month old history.
pub fn fixture_with(settings: Option<&str>, include_old: bool) -> Fixture {
    let dir = tempfile::tempdir().expect("temp dir");
    let seed = seed(dir.path(), settings, include_old);
    Fixture { dir, seed }
}

fn line(text: &str, x: u16, y: u16) -> NewLine {
    NewLine {
        text: String::from(text),
        x,
        y,
        w: 800,
        h: 100,
        source: LineSource::Ocr,
    }
}

fn frame(
    segment_id: i64,
    captured_at: i64,
    bundle_id: &str,
    app_name: &str,
    window_title: &str,
    url: Option<&str>,
    lines: Vec<NewLine>,
) -> NewFrame {
    NewFrame {
        captured_at,
        segment_id,
        pts_ms: 0,
        bundle_id: String::from(bundle_id),
        app_name: String::from(app_name),
        window_title: Some(String::from(window_title)),
        url: url.map(str::to_owned),
        change_ratio: 0.01,
        lines,
    }
}

fn seed(dir: &Path, settings: Option<&str>, include_old: bool) -> Seed {
    let now = now_ms();
    let store = Store::open(&dir.join("erst.sqlite")).expect("open store");
    let (other_frame_id, ordered_frame_id) = seed_frames(&store, now);
    let activity_day = seed_spans(&store, now);
    let (old_frame_id, old_day) = if include_old {
        let (id, day) = seed_old(&store, now);
        (Some(id), Some(day))
    } else {
        (None, None)
    };
    if let Some(settings) = settings {
        store
            .set_setting("settings.v1", settings)
            .expect("write settings");
    }
    Seed {
        other_frame_id,
        ordered_frame_id,
        old_frame_id,
        activity_day,
        old_day,
    }
}

/// One segment and four frames: a grouped pair, another app, and unordered lines.
fn seed_frames(store: &Store, now: i64) -> (i64, i64) {
    let segment_id = store
        .begin_segment(
            "segments/2026/10/20/120000-1.mp4",
            now - 3 * MS_PER_HOUR,
            1920,
            1080,
        )
        .expect("begin segment");
    store
        .finish_segment(segment_id, now - 2 * MS_PER_HOUR, VIDEO_BYTES)
        .expect("finish segment");

    store
        .insert_frame(&frame(
            segment_id,
            now - 2 * MS_PER_HOUR,
            APP_BUNDLE,
            APP_NAME,
            "Window",
            Some("https://example.com/docs"),
            vec![
                line("the zebra crossing", 100, 100),
                line("second line here", 100, 300),
            ],
        ))
        .expect("insert first frame");
    store
        .insert_frame(&frame(
            segment_id,
            now - 2 * MS_PER_HOUR + 5 * 60_000,
            APP_BUNDLE,
            APP_NAME,
            "Window",
            Some("https://example.com/docs"),
            vec![line("the zebra crossing again", 100, 120)],
        ))
        .expect("insert grouped frame");
    let other_frame_id = store
        .insert_frame(&frame(
            segment_id,
            now - 30 * 60_000,
            OTHER_BUNDLE,
            OTHER_NAME,
            "Notes",
            None,
            vec![line("zebra notes", 100, 100)],
        ))
        .expect("insert other frame");
    let ordered_frame_id = store
        .insert_frame(&frame(
            segment_id,
            now - 20 * 60_000,
            APP_BUNDLE,
            APP_NAME,
            "Window",
            None,
            vec![line("bottom text", 100, 300), line("top text", 100, 100)],
        ))
        .expect("insert ordered frame");
    (other_frame_id, ordered_frame_id)
}

/// Two closed spans on the local day around noon, far enough back to be complete.
fn seed_spans(store: &Store, now: i64) -> String {
    let anchor = now - 12 * MS_PER_HOUR;
    let day = local_date_of(anchor);
    let midnight = local_day_containing(anchor, local_offset_ms).start_ms;
    let xcode = store
        .begin_span(
            "com.apple.dt.Xcode",
            "Xcode",
            Some("Erst"),
            None,
            midnight + MS_PER_HOUR,
        )
        .expect("begin xcode span");
    store
        .end_span(xcode, midnight + 2 * MS_PER_HOUR)
        .expect("end xcode span");
    let safari = store
        .begin_span(
            "com.apple.Safari",
            "Safari",
            Some("Docs"),
            Some("https://example.com/docs"),
            midnight + 2 * MS_PER_HOUR,
        )
        .expect("begin safari span");
    store
        .end_span(safari, midnight + 2 * MS_PER_HOUR + MS_PER_HOUR / 2)
        .expect("end safari span");
    day
}

/// A month old segment and frame, used to test the agent history window.
fn seed_old(store: &Store, now: i64) -> (i64, String) {
    let old_segment = store
        .begin_segment("segments/old.mp4", now - 31 * MS_PER_DAY, 1920, 1080)
        .expect("begin old segment");
    store
        .finish_segment(old_segment, now - 30 * MS_PER_DAY, 0)
        .expect("finish old segment");
    let frame_id = store
        .insert_frame(&frame(
            old_segment,
            now - 30 * MS_PER_DAY,
            APP_BUNDLE,
            APP_NAME,
            "Archive",
            None,
            vec![line("zebra archive", 100, 100)],
        ))
        .expect("insert old frame");
    (frame_id, local_date_of(now - 30 * MS_PER_DAY))
}

/// Runs the binary against the fixture's data directory.
pub fn erst(fixture: &Fixture, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_erst"))
        .arg("--data-dir")
        .arg(fixture.dir.path())
        .args(args)
        .output()
        .expect("run erst")
}

pub fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("utf-8 stdout")
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("utf-8 stderr")
}

pub fn json_stdout(output: &Output) -> serde_json::Value {
    serde_json::from_slice(&output.stdout).expect("json stdout")
}
