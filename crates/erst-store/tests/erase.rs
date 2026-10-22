//! Erasing a time range: segments, frames, lines, spans, reminders, and the
//! bytes left on disk.

mod common;

use std::fs;
use std::path::Path;

use common::{line, open_store};
use erst_store::{EraseOutcome, NewFrame, NewLine, Store, StoreError};

/// Test results that may carry a row id or a count.
type Outcome<T = ()> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

const MINUTE_MS: i64 = 60_000;
const HOUR_MS: i64 = 3_600_000;
/// An arbitrary local day start. Erase logic only compares milliseconds.
const DAY: i64 = 1_700_000_000_000;
const ERASE_START: i64 = DAY + HOUR_MS + 30 * MINUTE_MS;
const ERASE_END: i64 = DAY + 3 * HOUR_MS + 20 * MINUTE_MS;

fn frame(segment_id: i64, captured_at: i64, lines: Vec<NewLine>) -> NewFrame {
    NewFrame {
        captured_at,
        segment_id,
        pts_ms: 0,
        bundle_id: "com.example.App".to_owned(),
        app_name: "Example".to_owned(),
        window_title: Some("Window".to_owned()),
        url: None,
        change_ratio: 0.01,
        lines,
    }
}

fn segment(store: &Store, path: &str, started_at: i64, ended_at: i64) -> Outcome<i64> {
    let id = store.begin_segment(path, started_at, 1920, 1080)?;
    store.finish_segment(id, ended_at, 1_000)?;
    Ok(id)
}

fn search_line_count(store: &Store, fts_match: &str) -> Outcome<usize> {
    Ok(store.search(&common::search_params(fts_match, 10))?.len())
}

fn assert_absent(path: &Path, needle: &[u8]) -> Outcome {
    if !path.exists() {
        return Ok(());
    }
    let bytes = fs::read(path)?;
    assert!(
        !bytes.windows(needle.len()).any(|window| window == needle),
        "{} still contains the erased text",
        path.display()
    );
    Ok(())
}

/// Three segments: two overlap the erased range, one survives.
fn seed_frames(store: &Store) -> Outcome {
    let first = segment(
        store,
        "segments/first.mp4",
        DAY + HOUR_MS,
        DAY + 2 * HOUR_MS,
    )?;
    let second = segment(
        store,
        "segments/second.mp4",
        DAY + 3 * HOUR_MS,
        DAY + 4 * HOUR_MS,
    )?;
    let survivor = segment(
        store,
        "segments/survivor.mp4",
        DAY + 6 * HOUR_MS,
        DAY + 7 * HOUR_MS,
    )?;

    // The first frame sits before the requested range and still goes, because
    // its segment is removed whole.
    store.insert_frame(&frame(
        first,
        DAY + HOUR_MS + 10 * MINUTE_MS,
        vec![line("erased alpha zebracrypt", 0)],
    ))?;
    store.insert_frame(&frame(
        first,
        DAY + HOUR_MS + 50 * MINUTE_MS,
        vec![line("erased beta", 0)],
    ))?;
    store.insert_frame(&frame(
        second,
        DAY + 3 * HOUR_MS + 30 * MINUTE_MS,
        vec![line("erased gamma", 0), line("shared keeper", 1)],
    ))?;
    // After the requested range, still removed with its segment.
    store.insert_frame(&frame(
        second,
        DAY + 3 * HOUR_MS + 50 * MINUTE_MS,
        vec![line("erased delta", 0), line("shared keeper", 1)],
    ))?;
    // The surviving frame keeps "shared keeper" alive.
    store.insert_frame(&frame(
        survivor,
        DAY + 6 * HOUR_MS + 30 * MINUTE_MS,
        vec![line("shared keeper", 0), line("survivor epsilon", 1)],
    ))?;
    Ok(())
}

/// One span per relationship to the erased range.
fn seed_spans(store: &Store) -> Outcome<i64> {
    let untouched = store.begin_span(
        "com.example.Before",
        "Before",
        Some("Window"),
        None,
        DAY + 30 * MINUTE_MS,
    )?;
    store.end_span(untouched, DAY + HOUR_MS)?;
    let left = store.begin_span(
        "com.example.Left",
        "Left",
        Some("Window"),
        None,
        DAY + HOUR_MS,
    )?;
    store.end_span(left, DAY + 2 * HOUR_MS)?;
    let inside = store.begin_span(
        "com.example.Inside",
        "Inside",
        Some("Window"),
        None,
        DAY + 2 * HOUR_MS,
    )?;
    store.end_span(inside, DAY + 2 * HOUR_MS + 30 * MINUTE_MS)?;
    let whole = store.begin_span(
        "com.example.Whole",
        "Whole",
        Some("Window"),
        Some("https://example.com/whole"),
        DAY + HOUR_MS + 15 * MINUTE_MS,
    )?;
    store.end_span(whole, DAY + 4 * HOUR_MS)?;
    let right = store.begin_span(
        "com.example.Right",
        "Right",
        Some("Window"),
        None,
        DAY + 2 * HOUR_MS + 45 * MINUTE_MS,
    )?;
    store.end_span(right, DAY + 3 * HOUR_MS + 40 * MINUTE_MS)?;
    let after = store.begin_span(
        "com.example.After",
        "After",
        Some("Window"),
        None,
        DAY + 5 * HOUR_MS,
    )?;
    store.end_span(after, DAY + 5 * HOUR_MS + 30 * MINUTE_MS)?;
    // An open span that started before the range covers it too.
    let open = store.begin_span(
        "com.example.Open",
        "Open",
        Some("Window"),
        None,
        DAY + HOUR_MS,
    )?;
    assert!(open > 0);
    Ok(open)
}

/// A reminder anchored to an erased frame and one anchored to the surviving
/// frame.
fn seed_reminders(store: &Store) -> Outcome {
    let erased_frame = store
        .search(&common::search_params("zebracrypt", 10))?
        .first()
        .map(|hit| hit.frame_id)
        .ok_or("seeded frame missing")?;
    store.add_reminder(Some(erased_frame), DAY, DAY + 9 * HOUR_MS, "erased note")?;
    let survivor_frame = store
        .search(&common::search_params("epsilon", 10))?
        .first()
        .map(|hit| hit.frame_id)
        .ok_or("surviving frame missing")?;
    store.add_reminder(
        Some(survivor_frame),
        DAY,
        DAY + 10 * HOUR_MS,
        "survivor note",
    )?;
    Ok(())
}

/// Seeds the store and returns the id of the open span that starts before the
/// erased range.
fn seed(store: &Store) -> Outcome<i64> {
    seed_frames(store)?;
    let open_span = seed_spans(store)?;
    seed_reminders(store)?;
    Ok(open_span)
}

#[test]
fn erase_removes_overlapping_segments_frames_lines_and_span_parts() -> Outcome {
    let (_dir, store) = open_store()?;
    let open_span = seed(&store)?;

    let outcome = store.erase_range(ERASE_START, ERASE_END)?;
    assert_eq!(
        outcome,
        EraseOutcome {
            frames_removed: 4,
            segment_paths: vec![
                "segments/first.mp4".to_owned(),
                "segments/second.mp4".to_owned(),
            ],
            // The union extends from the first segment start to the second
            // segment end, which is wider than the requested range.
            erased_from_ms: DAY + HOUR_MS,
            erased_to_ms: DAY + 4 * HOUR_MS,
            purge_complete: true,
        }
    );

    // Segments: only the survivor row is left.
    let segments = store.segments()?;
    assert_eq!(segments.len(), 1);
    assert_eq!(segments[0].path.as_deref(), Some("segments/survivor.mp4"));
    assert_eq!(store.frames_in_range(DAY, DAY + 24 * HOUR_MS)?.len(), 1);

    // Lines: unique erased text is gone, the shared line stays, and FTS agrees.
    assert_eq!(search_line_count(&store, "zebracrypt")?, 0);
    assert_eq!(search_line_count(&store, "erased")?, 0);
    assert_eq!(search_line_count(&store, "shared")?, 1);
    assert_eq!(search_line_count(&store, "epsilon")?, 1);
    let stats = store.storage_stats(DAY + 24 * HOUR_MS)?;
    // The survived frame's two lines and its window title.
    assert_eq!(stats.unique_line_count, 3);

    // Spans: untouched, clipped at the start, deleted, split in two, clipped at
    // the end, untouched, and the open one split into an open tail.
    let spans = store.spans_in_range(DAY, DAY + 24 * HOUR_MS)?;
    let app = |bundle_id: &str| -> Vec<(i64, Option<i64>)> {
        spans
            .iter()
            .filter(|span| span.bundle_id == bundle_id)
            .map(|span| (span.started_at, span.ended_at))
            .collect()
    };
    assert_eq!(
        app("com.example.Before"),
        vec![(DAY + 30 * MINUTE_MS, Some(DAY + HOUR_MS))]
    );
    assert_eq!(
        app("com.example.Left"),
        vec![(DAY + HOUR_MS, Some(ERASE_START))]
    );
    assert_eq!(app("com.example.Inside"), Vec::<(i64, Option<i64>)>::new());
    assert_eq!(
        app("com.example.Whole"),
        vec![
            (DAY + HOUR_MS + 15 * MINUTE_MS, Some(ERASE_START)),
            (ERASE_END, Some(DAY + 4 * HOUR_MS)),
        ]
    );
    assert_eq!(
        app("com.example.Right"),
        vec![(ERASE_END, Some(DAY + 3 * HOUR_MS + 40 * MINUTE_MS))]
    );
    assert_eq!(
        app("com.example.After"),
        vec![(DAY + 5 * HOUR_MS, Some(DAY + 5 * HOUR_MS + 30 * MINUTE_MS))]
    );
    assert_eq!(
        app("com.example.Open"),
        vec![(DAY + HOUR_MS, Some(ERASE_START)), (ERASE_END, None)]
    );
    // The open row keeps its id as the tail, because the focus tracker closes
    // that id later. Only the before piece is new.
    let open_rows = spans
        .iter()
        .filter(|span| span.bundle_id == "com.example.Open")
        .collect::<Vec<_>>();
    assert_ne!(open_rows[0].id, open_span);
    assert_eq!(open_rows[1].id, open_span);

    // Reminders keep their rows; the erased one loses its anchor.
    let reminders = store.reminders()?;
    assert_eq!(reminders.len(), 2);
    let erased = reminders
        .iter()
        .find(|reminder| reminder.note == "erased note")
        .ok_or("erased reminder missing")?;
    assert_eq!(erased.frame_id, None);
    let survivor_reminder = reminders
        .iter()
        .find(|reminder| reminder.note == "survivor note")
        .ok_or("survivor reminder missing")?;
    assert!(survivor_reminder.frame_id.is_some());
    Ok(())
}

#[test]
fn erased_text_is_absent_from_the_database_and_wal_bytes() -> Outcome {
    let (dir, store) = open_store()?;
    seed(&store)?;
    let survivor = store
        .search(&common::search_params("epsilon", 10))?
        .into_iter()
        .flat_map(|hit| hit.matched_lines)
        .map(|line| line.text)
        .collect::<Vec<String>>();
    assert_eq!(survivor, vec!["survivor epsilon".to_owned()]);

    store.erase_range(ERASE_START, ERASE_END)?;

    let database = dir.path().join("erst.sqlite");
    let wal = dir.path().join("erst.sqlite-wal");
    assert_absent(&database, b"zebracrypt")?;
    assert_absent(&wal, b"zebracrypt")?;
    assert_absent(&database, b"erased alpha")?;
    assert_absent(&wal, b"erased alpha")?;

    // The surviving text is still readable from the database file.
    let bytes = fs::read(&database)?;
    assert!(
        bytes
            .windows(b"survivor epsilon".len())
            .any(|window| window == b"survivor epsilon")
    );

    // The erase vacuums free pages and truncates the WAL.
    let connection = rusqlite::Connection::open(&database)?;
    let free_pages: i64 =
        connection.pragma_query_value(None, "freelist_count", |row| row.get(0))?;
    assert_eq!(free_pages, 0);
    assert_eq!(fs::metadata(&wal).map_or(0, |meta| meta.len()), 0);
    Ok(())
}

#[test]
fn erase_with_an_empty_range_changes_nothing() -> Outcome {
    let (_dir, store) = open_store()?;
    seed(&store)?;
    let outcome = store.erase_range(ERASE_END, ERASE_START)?;
    assert_eq!(outcome.frames_removed, 0);
    assert_eq!(outcome.segment_paths, Vec::<String>::new());
    assert_eq!(store.segments()?.len(), 3);
    assert_eq!(store.frames_in_range(DAY, DAY + 24 * HOUR_MS)?.len(), 5);
    Ok(())
}

#[test]
fn erase_removes_an_open_segment_and_reports_its_start() -> Outcome {
    let (_dir, store) = open_store()?;
    let survivor = segment(
        &store,
        "segments/survivor.mp4",
        DAY + 6 * HOUR_MS,
        DAY + 7 * HOUR_MS,
    )?;
    store.insert_frame(&frame(
        survivor,
        DAY + 6 * HOUR_MS + 10 * MINUTE_MS,
        vec![line("survivor epsilon", 0)],
    ))?;
    // An open segment counts as extending past every requested end.
    let open = store.begin_segment("segments/open.mp4", DAY + HOUR_MS, 1920, 1080)?;
    store.insert_frame(&frame(
        open,
        DAY + HOUR_MS + 5 * MINUTE_MS,
        vec![line("open zebracrypt", 0)],
    ))?;
    store.insert_frame(&frame(open, DAY + 4 * HOUR_MS, vec![line("open late", 0)]))?;

    let outcome = store.erase_range(ERASE_START, ERASE_END)?;
    assert_eq!(
        outcome,
        EraseOutcome {
            frames_removed: 2,
            segment_paths: vec!["segments/open.mp4".to_owned()],
            // The open segment started before the request and has no end, so
            // only its start widens the union.
            erased_from_ms: DAY + HOUR_MS,
            erased_to_ms: ERASE_END,
            purge_complete: true,
        }
    );
    assert!(store.open_segment()?.is_none());
    assert_eq!(store.segments()?.len(), 1);
    assert_eq!(search_line_count(&store, "zebracrypt")?, 0);
    assert_eq!(search_line_count(&store, "epsilon")?, 1);
    Ok(())
}

#[test]
fn erase_removes_a_frame_inside_the_range_from_a_surviving_segment() -> Outcome {
    let (_dir, store) = open_store()?;
    let segment_id = segment(
        &store,
        "segments/kept.mp4",
        DAY + 6 * HOUR_MS,
        DAY + 7 * HOUR_MS,
    )?;
    let safe = store.insert_frame(&frame(
        segment_id,
        DAY + 6 * HOUR_MS + 10 * MINUTE_MS,
        vec![line("survivor epsilon", 0)],
    ))?;
    // Clock skew can put a frame inside the range while its segment is not
    // overlapping. The frame still goes.
    let inside = store.insert_frame(&frame(
        segment_id,
        DAY + 2 * HOUR_MS,
        vec![line("skewed zebracrypt", 0)],
    ))?;

    let outcome = store.erase_range(ERASE_START, ERASE_END)?;
    assert_eq!(outcome.frames_removed, 1);
    assert_eq!(outcome.segment_paths, Vec::<String>::new());
    assert_eq!(outcome.erased_from_ms, ERASE_START);
    assert_eq!(outcome.erased_to_ms, ERASE_END);
    assert_eq!(store.segments()?.len(), 1);
    assert_eq!(
        store
            .frames_in_range(DAY, DAY + 24 * HOUR_MS)?
            .iter()
            .map(|stamp| stamp.id)
            .collect::<Vec<_>>(),
        vec![safe]
    );
    assert_ne!(safe, inside);
    assert_eq!(search_line_count(&store, "zebracrypt")?, 0);
    assert_eq!(search_line_count(&store, "epsilon")?, 1);
    Ok(())
}

#[test]
fn delete_segment_removes_its_frames_but_keeps_shared_lines() -> Outcome {
    let (_dir, store) = open_store()?;
    seed(&store)?;
    let segments = store.segments()?;
    let second = segments
        .iter()
        .find(|segment| segment.path.as_deref() == Some("segments/second.mp4"))
        .ok_or("second segment missing")?
        .id;

    assert_eq!(
        store.delete_segment(second)?,
        Some("segments/second.mp4".to_owned())
    );
    assert_eq!(store.segments()?.len(), 2);
    assert_eq!(search_line_count(&store, "erased gamma")?, 0);
    // The shared line survives because the untouched frame still uses it.
    assert_eq!(search_line_count(&store, "shared")?, 1);
    assert!(matches!(
        store.delete_segment(second),
        Err(StoreError::NotFound {
            what: "segment",
            ..
        })
    ));

    // A segment whose video is already gone returns no path.
    let survivor = store
        .segments()?
        .into_iter()
        .find(|segment| segment.path.as_deref() == Some("segments/survivor.mp4"))
        .ok_or("survivor segment missing")?;
    store.delete_segment_video(survivor.id)?;
    assert_eq!(store.delete_segment(survivor.id)?, None);
    Ok(())
}

#[test]
fn erase_keeps_the_open_span_id_on_the_tail_after_the_range() -> Outcome {
    let (_dir, store) = open_store()?;
    let span = store.begin_span("com.example.Open", "Open", Some("Window"), None, 0)?;

    store.erase_range(100, 200)?;
    store.end_span(span, 300)?;

    let spans = store.spans_in_range(0, 1_000)?;
    assert_eq!(
        spans.len(),
        2,
        "the split leaves one closed piece and the tail"
    );
    assert_ne!(spans[0].id, span);
    assert_eq!((spans[0].started_at, spans[0].ended_at), (0, Some(100)));
    // The focus tracker holds this id, so the row it closes is the tail.
    assert_eq!(spans[1].id, span);
    assert_eq!((spans[1].started_at, spans[1].ended_at), (200, Some(300)));
    assert_eq!(store.spans_in_range(100, 200)?, Vec::new());
    assert!(
        store
            .spans_in_range(0, 1_000)?
            .iter()
            .all(|span| span.ended_at.is_some())
    );
    Ok(())
}

#[test]
fn delete_segment_purges_the_erased_text_from_the_database_and_wal() -> Outcome {
    let (dir, store) = open_store()?;
    seed(&store)?;
    let second = store
        .segments()?
        .into_iter()
        .find(|segment| segment.path.as_deref() == Some("segments/second.mp4"))
        .ok_or("second segment missing")?
        .id;

    store.delete_segment(second)?;

    let database = dir.path().join("erst.sqlite");
    let wal = dir.path().join("erst.sqlite-wal");
    assert_absent(&database, b"erased gamma")?;
    assert_absent(&wal, b"erased gamma")?;
    assert_absent(&database, b"erased delta")?;
    assert_absent(&wal, b"erased delta")?;

    let connection = rusqlite::Connection::open(&database)?;
    let free_pages: i64 =
        connection.pragma_query_value(None, "freelist_count", |row| row.get(0))?;
    assert_eq!(free_pages, 0);
    assert_eq!(fs::metadata(&wal).map_or(0, |meta| meta.len()), 0);
    Ok(())
}

#[test]
fn erase_queues_detached_videos_until_the_caller_unlinks_them() -> Outcome {
    let (_dir, store) = open_store()?;
    seed(&store)?;

    let outcome = store.erase_range(ERASE_START, ERASE_END)?;
    assert!(outcome.purge_complete);
    assert_eq!(
        store.pending_unlinks()?,
        vec![
            "segments/first.mp4".to_owned(),
            "segments/second.mp4".to_owned()
        ]
    );

    store.unlink_done("segments/first.mp4")?;
    assert_eq!(
        store.pending_unlinks()?,
        vec!["segments/second.mp4".to_owned()]
    );
    // Dropping an already handled path is harmless.
    store.unlink_done("segments/first.mp4")?;
    assert_eq!(
        store.pending_unlinks()?,
        vec!["segments/second.mp4".to_owned()]
    );
    Ok(())
}

#[test]
fn pending_unlinks_survive_reopening_the_store() -> Outcome {
    let (dir, store) = open_store()?;
    seed(&store)?;
    store.erase_range(ERASE_START, ERASE_END)?;
    drop(store);

    let reopened = Store::open(&dir.path().join("erst.sqlite"))?;
    assert_eq!(
        reopened.pending_unlinks()?,
        vec![
            "segments/first.mp4".to_owned(),
            "segments/second.mp4".to_owned()
        ]
    );
    Ok(())
}
