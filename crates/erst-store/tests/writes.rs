//! Writes: deduplication, app identity, settings, and read-only rejection.

mod common;

use common::{
    APP, APP_NAME, TITLE, TestResult, begin_segment, frame, line, open_store, search_params,
    simple_frame,
};
use erst_store::{LineSource, NewFrame, NewLine, StoreError};

#[test]
fn insert_frame_stores_shared_lines_once() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let shared = [
        "shared 0", "shared 1", "shared 2", "shared 3", "shared 4", "shared 5", "shared 6",
        "shared 7", "shared 8",
    ];
    let mut first_lines: Vec<&str> = shared.to_vec();
    first_lines.push("only first");
    let mut second_lines: Vec<&str> = shared.to_vec();
    second_lines.push("only second");

    store.insert_frame(&simple_frame(segment_id, 1_000, &first_lines))?;
    store.insert_frame(&simple_frame(segment_id, 2_000, &second_lines))?;

    let stats = store.storage_stats(10_000)?;
    assert_eq!(stats.frame_count, 2);
    // Nine shared lines, one line of each frame alone, and the shared title.
    assert_eq!(stats.unique_line_count, 12);
    Ok(())
}

#[test]
fn identical_and_whitespace_lines_share_one_row() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let new_frame = frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some("Window"),
        vec![
            line("  Alpha \t  beta  ", 0),
            line("Alpha beta", 1),
            line("  \t\n ", 2),
        ],
    );
    let frame_id = store.insert_frame(&new_frame)?;

    assert_eq!(store.storage_stats(10_000)?.unique_line_count, 2);
    let hits = store.search(&search_params("\"Alpha beta\"", 10))?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, frame_id);
    assert_eq!(hits[0].matched_lines.len(), 2);
    assert_eq!(hits[0].matched_lines[0].y, 100);
    assert_eq!(hits[0].matched_lines[1].y, 300);
    Ok(())
}

#[test]
fn identical_lines_on_one_row_keep_a_box_for_each_position() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let new_frame = frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![
            NewLine {
                text: "OK".to_owned(),
                x: 100,
                y: 500,
                w: 80,
                h: 40,
                source: LineSource::Ocr,
            },
            NewLine {
                text: "OK".to_owned(),
                x: 900,
                y: 500,
                w: 80,
                h: 40,
                source: LineSource::Ocr,
            },
        ],
    );
    let frame_id = store.insert_frame(&new_frame)?;

    let lines = store.frame_detail(frame_id)?.lines;
    assert_eq!(lines.len(), 2, "two OK buttons on one row are two boxes");
    assert_eq!((lines[0].x, lines[0].y), (100, 500));
    assert_eq!((lines[1].x, lines[1].y), (900, 500));
    // The two OK boxes share one line; the window title is a line of its own.
    assert_eq!(store.storage_stats(10_000)?.unique_line_count, 2);
    Ok(())
}

#[test]
fn upsert_app_updates_the_display_name() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        1_000,
        APP,
        "Old Name",
        Some(TITLE),
        vec![line("app name", 0)],
    ))?;

    let first = store.upsert_app(APP, "Old Name")?;
    let second = store.upsert_app(APP, "New Name")?;
    assert_eq!(first, second);

    let detail = store.frame_detail(frame_id)?;
    assert_eq!(detail.app_name, "New Name");
    assert_eq!(detail.bundle_id, APP);
    Ok(())
}

#[test]
fn settings_and_excluded_apps_round_trip() -> TestResult {
    let (_dir, store) = open_store()?;
    store.set_setting("captureIntervalMs", "2000")?;
    store.set_setting("captureIntervalMs", "4000")?;
    store.set_setting("theme", "dark")?;

    let settings = store.settings()?;
    assert_eq!(settings.len(), 2);
    assert_eq!(settings.get("captureIntervalMs"), Some(&"4000".to_owned()));
    assert_eq!(settings.get("theme"), Some(&"dark".to_owned()));

    store.set_excluded_apps(&["com.a".to_owned(), "com.b".to_owned()])?;
    assert_eq!(store.excluded_apps()?, vec!["com.a", "com.b"]);
    store.set_excluded_apps(&["com.c".to_owned()])?;
    assert_eq!(store.excluded_apps()?, vec!["com.c"]);
    store.set_excluded_apps(&[])?;
    assert_eq!(store.excluded_apps()?.len(), 0);
    Ok(())
}

#[test]
fn read_only_store_serves_reads_and_rejects_writes() -> TestResult {
    let (dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["read only needle"]))?;
    let path = dir.path().join("erst.sqlite");
    drop(store);

    let read_only = erst_store::Store::open_read_only(&path)?;
    let hits = read_only.search(&search_params("needle", 10))?;
    assert_eq!(hits.len(), 1);

    assert!(matches!(
        read_only.upsert_app("com.example.Other", "Other"),
        Err(StoreError::ReadOnly)
    ));
    assert!(matches!(
        read_only.begin_segment("segments/b.mp4", 2, 100, 100),
        Err(StoreError::ReadOnly)
    ));
    let frame = NewFrame {
        captured_at: 2_000,
        segment_id,
        pts_ms: 0,
        bundle_id: "com.example.Other".to_owned(),
        app_name: "Other".to_owned(),
        window_title: None,
        url: None,
        change_ratio: 0.0,
        lines: Vec::new(),
    };
    assert!(matches!(
        read_only.insert_frame(&frame),
        Err(StoreError::ReadOnly)
    ));
    Ok(())
}
