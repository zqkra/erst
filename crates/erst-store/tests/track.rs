//! Timeline track: the frames of a range with the app, window title, and page they showed.

mod common;

use common::{APP, APP_NAME, TestResult, begin_segment, frame, open_store};
use rusqlite::Connection;

/// The statement `Store::track_frames` runs. It is repeated here because the
/// store keeps its SQL private and this test reads the plan the reader's
/// connection picks for that statement.
const SELECT_TRACK_FRAMES: &str = "
    SELECT f.id, f.captured_at, f.change_ratio, a.bundle_id, a.name, f.window_title, f.url
    FROM frames f
    LEFT JOIN apps a ON a.id = f.app_id
    WHERE f.captured_at >= ?1 AND f.captured_at < ?2
    ORDER BY f.captured_at, f.id";

#[test]
fn track_frames_returns_the_range_oldest_first_with_app_title_and_url() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let mut page = frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some("encoder.rs"),
        Vec::new(),
    );
    page.url = Some("https://example.com/a".to_owned());
    page.change_ratio = 0.42;
    let first = store.insert_frame(&page)?;
    let second = store.insert_frame(&frame(
        segment_id,
        2_000,
        "com.example.Other",
        "Other",
        None,
        Vec::new(),
    ))?;
    let third = store.insert_frame(&frame(
        segment_id,
        3_000,
        APP,
        APP_NAME,
        Some("lib.rs"),
        Vec::new(),
    ))?;
    store.insert_frame(&frame(segment_id, 4_000, APP, APP_NAME, None, Vec::new()))?;

    let rows = store.track_frames(1_000, 3_500)?;
    assert_eq!(
        rows.iter().map(|row| row.id).collect::<Vec<_>>(),
        vec![first, second, third]
    );
    assert_eq!(rows[0].captured_at, 1_000);
    assert_eq!(rows[0].change_ratio, 0.42);
    assert_eq!(rows[0].bundle_id.as_deref(), Some(APP));
    assert_eq!(rows[0].app_name.as_deref(), Some(APP_NAME));
    assert_eq!(rows[0].window_title.as_deref(), Some("encoder.rs"));
    assert_eq!(rows[0].url.as_deref(), Some("https://example.com/a"));
    assert_eq!(rows[1].bundle_id.as_deref(), Some("com.example.Other"));
    assert!(rows[1].window_title.is_none());
    assert_eq!(rows[2].window_title.as_deref(), Some("lib.rs"));
    assert!(rows[2].url.is_none());
    Ok(())
}

#[test]
fn track_frames_is_half_open() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let first = store.insert_frame(&frame(segment_id, 1_000, APP, APP_NAME, None, Vec::new()))?;
    let second = store.insert_frame(&frame(segment_id, 2_000, APP, APP_NAME, None, Vec::new()))?;
    store.insert_frame(&frame(segment_id, 3_000, APP, APP_NAME, None, Vec::new()))?;

    let rows = store.track_frames(2_000, 3_000)?;
    assert_eq!(
        rows.iter().map(|row| row.id).collect::<Vec<_>>(),
        vec![second]
    );
    assert_eq!(store.track_frames(500, 1_000)?.len(), 0);
    assert_eq!(store.track_frames(3_000, 2_000)?.len(), 0);
    assert_eq!(
        store.track_frames(0, 10_000)?.first().map(|row| row.id),
        Some(first)
    );
    Ok(())
}

#[test]
fn track_frames_seek_the_captured_at_index_without_a_sort() -> TestResult {
    let (dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&frame(segment_id, 1_000, APP, APP_NAME, None, Vec::new()))?;

    let connection = Connection::open(dir.path().join("erst.sqlite"))?;
    let sql = format!("EXPLAIN QUERY PLAN {SELECT_TRACK_FRAMES}");
    let mut statement = connection.prepare(&sql)?;
    let plan = statement
        .query_map(rusqlite::params![0_i64, 10_000_i64], |row| {
            row.get::<_, String>(3)
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let plan = plan.join("\n");
    assert!(plan.contains("frames_captured_at"), "{plan}");
    assert!(!plan.contains("SCAN f"), "{plan}");
    assert!(!plan.contains("TEMP B-TREE"), "{plan}");
    Ok(())
}
