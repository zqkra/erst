//! Helpers shared by the `erst-ffi` integration tests.
//!
//! Each test binary uses a different subset, so unused helpers are allowed here.

#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use erst_ffi::{Engine, FfiLineSource, FfiNewFrame, FfiTextLine};
use tempfile::TempDir;

/// Bundle identifier of the app the test frames belong to.
pub const SAFARI: &str = "com.apple.Safari";

/// Opens an engine on a fresh temporary data directory.
pub fn open_engine() -> (TempDir, PathBuf, Arc<Engine>) {
    let temp = tempfile::tempdir().expect("a temporary directory");
    let data_dir = temp.path().join("data");
    let engine = Engine::open(data_dir.to_string_lossy().into_owned()).expect("the engine opens");
    (temp, data_dir, engine)
}

/// The current wall clock in Unix milliseconds.
pub fn current_time_ms() -> i64 {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("the clock is after the epoch");
    i64::try_from(elapsed.as_millis()).expect("the millisecond count fits in an i64")
}

/// One stored text line at a fixed position, read from the pixels.
pub fn text_line(text: &str, y: u16) -> FfiTextLine {
    FfiTextLine {
        text: text.to_owned(),
        x: 100,
        y,
        w: 4_000,
        h: 300,
        source: FfiLineSource::Ocr,
    }
}

/// A kept frame of the test app carrying one text line.
pub fn frame(segment_id: i64, captured_at_ms: i64, text: &str) -> FfiNewFrame {
    FfiNewFrame {
        captured_at_ms,
        segment_id,
        pts_ms: 0,
        bundle_id: SAFARI.to_owned(),
        app_name: "Safari".to_owned(),
        window_title: Some("Apple".to_owned()),
        url: None,
        change_ratio: 0.5,
        lines: vec![text_line(text, 200)],
    }
}

/// Writes a stand-in video file so retention and erase have something to delete.
pub fn write_video(data_dir: &Path, relative_path: &str) -> PathBuf {
    let path = data_dir.join(relative_path);
    let parent = path.parent().expect("a segment path has a parent");
    fs::create_dir_all(parent).expect("the segment directory is created");
    fs::write(&path, b"not a real video").expect("the stand-in video is written");
    path
}
