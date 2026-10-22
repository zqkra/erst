//! End to end tests of the read-only CLI commands.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::process::{Command, Stdio};

use common::{
    APP_NAME, OTHER_BUNDLE, OTHER_NAME, VIDEO_BYTES, erst, fixture, json_stdout, stderr, stdout,
};
use serde_json::Value;

#[test]
fn search_json_returns_moments_with_matched_lines() {
    let fixture = fixture();
    let output = erst(&fixture, &["search", "zebra", "--json"]);
    assert!(output.status.success(), "{}", stderr(&output));
    let hits = json_stdout(&output);
    let hits = hits.as_array().unwrap();
    assert_eq!(hits.len(), 2, "{hits:?}");
    assert_eq!(hits[0]["frame_id"], fixture.seed.other_frame_id);
    assert_eq!(hits[0]["app"], OTHER_NAME);
    assert_eq!(hits[0]["matched_lines"][0], "zebra notes");
    assert_eq!(hits[1]["app"], APP_NAME);
    assert_eq!(hits[1]["window_title"], "Window");
    assert_eq!(hits[1]["bundle_id"], common::APP_BUNDLE);
    assert!(hits[1]["time"].as_str().unwrap().contains('T'));
    let first_seen = hits[1]["first_seen_ms"].as_i64().unwrap();
    let last_seen = hits[1]["last_seen_ms"].as_i64().unwrap();
    assert!(first_seen <= last_seen);
}

#[test]
fn search_json_applies_an_app_filter() {
    let fixture = fixture();
    let output = erst(
        &fixture,
        &["search", "zebra", "app:\"Other App\"", "--json"],
    );
    assert!(output.status.success(), "{}", stderr(&output));
    let hits = json_stdout(&output);
    let hits = hits.as_array().unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0]["bundle_id"], OTHER_BUNDLE);
    assert_eq!(hits[0]["matched_lines"][0], "zebra notes");
}

#[test]
fn search_text_is_readable_and_has_no_escape_codes() {
    let fixture = fixture();
    let output = erst(&fixture, &["search", "zebra"]);
    assert!(output.status.success(), "{}", stderr(&output));
    let text = stdout(&output);
    assert!(text.contains("zebra notes"));
    assert!(text.contains("Example"));
    assert!(text.contains("Other App"));
    assert!(text.contains("https://example.com/docs"));
    assert!(!text.contains('\u{1b}'));
    assert!(
        text.lines()
            .any(|line| line.contains("Example") && line.contains("  Window")),
        "{text}"
    );
}

#[test]
fn search_without_words_explains_the_problem() {
    let fixture = fixture();
    let output = erst(&fixture, &["search", "app:Safari"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(stderr(&output).contains("nothing to search for"));
}

#[test]
fn stats_json_reports_storage_and_counts() {
    let fixture = fixture();
    let output = erst(&fixture, &["stats", "--json"]);
    assert!(output.status.success(), "{}", stderr(&output));
    let stats: Value = json_stdout(&output);
    assert_eq!(stats["frame_count"], 4);
    assert_eq!(stats["segment_count"], 1);
    // Six distinct lines plus the two window titles of the fixture.
    assert_eq!(stats["unique_line_count"], 8);
    assert_eq!(stats["video_bytes"], VIDEO_BYTES);
    assert!(stats["database_bytes"].as_u64().unwrap() > 0);
    assert!(stats["average_bytes_per_day"].as_u64().unwrap() > 0);
    assert!(stats["oldest"].as_str().unwrap().contains("2026"));
    let database = stats["database"].as_str().unwrap();
    assert!(
        database.ends_with("KB") || database.ends_with("MB"),
        "{database}"
    );
}

#[test]
fn stats_text_uses_human_rows() {
    let fixture = fixture();
    let output = erst(&fixture, &["stats"]);
    assert!(output.status.success(), "{}", stderr(&output));
    let text = stdout(&output);
    for label in [
        "Database",
        "Video",
        "Segments",
        "Frames",
        "Unique lines",
        "Average/day",
    ] {
        assert!(text.contains(label), "missing {label}: {text}");
    }
    assert!(text.contains("5.0 MB"), "{text}");
    assert!(!text.contains('\u{1b}'));
}

#[test]
fn activity_json_totals_the_seeded_day() {
    let fixture = fixture();
    let output = erst(
        &fixture,
        &["activity", "--day", &fixture.seed.activity_day, "--json"],
    );
    assert!(output.status.success(), "{}", stderr(&output));
    let activity: Value = json_stdout(&output);
    assert_eq!(activity["day"], fixture.seed.activity_day);
    let total = activity["total_ms"].as_i64().unwrap();
    assert!(total >= 5_400_000, "{total}");
    assert!(activity["end_ms"].as_i64().unwrap() > activity["start_ms"].as_i64().unwrap());
    let categories = activity["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 4);
    let building = categories
        .iter()
        .find(|category| category["category"] == "building")
        .unwrap();
    assert!(building["ms"].as_i64().unwrap() >= 3_000_000);
    let apps = activity["apps"].as_array().unwrap();
    let xcode = apps
        .iter()
        .find(|app| app["bundle_id"] == "com.apple.dt.Xcode")
        .unwrap();
    assert_eq!(xcode["name"], "Xcode");
    let websites = activity["websites"].as_array().unwrap();
    assert_eq!(websites[0]["host"], "example.com");
}

#[test]
fn activity_text_names_categories_and_apps() {
    let fixture = fixture();
    let output = erst(&fixture, &["activity", "--day", &fixture.seed.activity_day]);
    assert!(output.status.success(), "{}", stderr(&output));
    let text = stdout(&output);
    assert!(text.contains(&fixture.seed.activity_day));
    assert!(text.contains("Building"));
    assert!(text.contains("Xcode"));
    assert!(text.contains("example.com"));
    assert!(!text.contains('\u{1b}'));
}

#[test]
fn missing_database_exits_with_code_two() {
    let dir = tempfile::tempdir().unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_erst"))
        .arg("--data-dir")
        .arg(dir.path())
        .arg("stats")
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(stderr(&output).contains("no Erst database"));
}

#[test]
fn data_dir_environment_variable_is_honored() {
    let fixture = fixture();
    let output = Command::new(env!("CARGO_BIN_EXE_erst"))
        .env("ERST_DATA_DIR", fixture.dir.path())
        .args(["stats", "--json"])
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", stderr(&output));
    let stats = json_stdout(&output);
    assert_eq!(stats["frame_count"], 4);
}
