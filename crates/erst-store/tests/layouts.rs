//! Packed frame layouts and line runs: what search and erase rely on.

mod common;

use std::path::Path;

use common::{TestResult, search_params, simple_frame};
use erst_store::{SearchPlan, Store};
use rusqlite::Connection;

/// Frames sit twenty minutes apart, so every frame is its own search moment.
const FRAME_SPACING_MS: i64 = 20 * 60 * 1_000;
/// Each frame gets its own closed segment, so an erase can take one frame.
const SEGMENT_LENGTH_MS: i64 = 1_000;

fn open() -> Result<(tempfile::TempDir, Store), Box<dyn std::error::Error + Send + Sync>> {
    let dir = tempfile::tempdir()?;
    let store = Store::open(&dir.path().join("erst.sqlite"))?;
    Ok((dir, store))
}

/// Inserts frame number `slot` showing `lines`, and returns its id.
fn insert(
    store: &Store,
    slot: i64,
    lines: &[&str],
) -> Result<i64, Box<dyn std::error::Error + Send + Sync>> {
    let start = slot * FRAME_SPACING_MS;
    let segment = store.begin_segment(&format!("segments/{slot}.mp4"), start, 1920, 1080)?;
    store.finish_segment(segment, start + SEGMENT_LENGTH_MS, 1)?;
    Ok(store.insert_frame(&simple_frame(segment, start + SEGMENT_LENGTH_MS / 2, lines))?)
}

fn erase_slot(store: &Store, slot: i64) -> TestResult {
    let start = slot * FRAME_SPACING_MS;
    store.erase_range(start, start + SEGMENT_LENGTH_MS)?;
    Ok(())
}

fn runs(
    path: &Path,
    text: &str,
) -> Result<Vec<(i64, i64)>, Box<dyn std::error::Error + Send + Sync>> {
    let connection = Connection::open(path)?;
    let mut statement = connection.prepare(
        "SELECT r.first_frame, r.last_frame FROM line_runs r
         JOIN text_lines t ON t.id = r.line_id WHERE t.text = ?1 ORDER BY r.first_frame",
    )?;
    let rows = statement.query_map([text], |row| Ok((row.get(0)?, row.get(1)?)))?;
    Ok(rows.collect::<Result<_, _>>()?)
}

fn found(store: &Store, word: &str) -> Result<Vec<i64>, Box<dyn std::error::Error + Send + Sync>> {
    let mut frames: Vec<i64> = store
        .search(&search_params(&format!("\"{word}\""), 50))?
        .into_iter()
        .map(|hit| hit.frame_id)
        .collect();
    frames.sort_unstable();
    Ok(frames)
}

#[test]
fn a_run_follows_a_line_across_frames_and_ends_where_it_disappears() -> TestResult {
    let (dir, store) = open()?;
    let first = insert(&store, 0, &["alpha"])?;
    let second = insert(&store, 1, &["alpha", "beta"])?;
    let third = insert(&store, 2, &["alpha"])?;
    let gap = insert(&store, 3, &["beta"])?;
    let back = insert(&store, 4, &["alpha"])?;

    let path = dir.path().join("erst.sqlite");
    assert_eq!(runs(&path, "alpha")?, vec![(first, third), (back, back)]);
    assert_eq!(runs(&path, "beta")?, vec![(second, second), (gap, gap)]);
    assert_eq!(found(&store, "alpha")?, vec![first, second, third, back]);
    assert_eq!(found(&store, "beta")?, vec![second, gap]);
    Ok(())
}

#[test]
fn a_reused_frame_id_never_inherits_the_lines_of_erased_frames() -> TestResult {
    let (dir, store) = open()?;
    let kept = insert(&store, 0, &["secret"])?;
    let erased = insert(&store, 1, &["secret"])?;
    insert(&store, 2, &["secret"])?;
    erase_slot(&store, 1)?;
    erase_slot(&store, 2)?;

    // SQLite gives the next row the id after the largest one left, which the
    // erased frames used to hold.
    let reused = insert(&store, 3, &["public"])?;
    assert_eq!(reused, erased);
    assert_eq!(
        runs(&dir.path().join("erst.sqlite"), "secret")?,
        vec![(kept, kept)]
    );
    assert_eq!(found(&store, "secret")?, vec![kept]);
    assert_eq!(found(&store, "public")?, vec![reused]);
    Ok(())
}

#[test]
fn erasing_a_middle_frame_keeps_the_others_and_the_last_one_takes_the_line() -> TestResult {
    let (dir, store) = open()?;
    let first = insert(&store, 0, &["gamma"])?;
    insert(&store, 1, &["gamma"])?;
    let last = insert(&store, 2, &["gamma"])?;
    erase_slot(&store, 1)?;

    let path = dir.path().join("erst.sqlite");
    assert_eq!(runs(&path, "gamma")?, vec![(first, last)]);
    assert_eq!(found(&store, "gamma")?, vec![first, last]);

    erase_slot(&store, 0)?;
    assert_eq!(runs(&path, "gamma")?, vec![(last, last)]);
    erase_slot(&store, 2)?;
    assert_eq!(runs(&path, "gamma")?, Vec::new());
    let lines: i64 = Connection::open(&path)?.query_row(
        "SELECT COUNT(*) FROM text_lines WHERE text = 'gamma'",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(lines, 0, "a line no frame shows anymore must go");
    Ok(())
}

#[test]
fn both_search_plans_find_the_same_frames() -> TestResult {
    let (_dir, store) = open()?;
    for slot in 0..30 {
        let words: &[&str] = match slot % 3 {
            0 => &["common", "rare words"],
            1 => &["common"],
            _ => &["other"],
        };
        insert(&store, slot, words)?;
    }
    for word in ["common", "rare", "other"] {
        let params = search_params(&format!("\"{word}\""), 50);
        let mut by_lines: Vec<i64> = store
            .search_with_plan(&params, SearchPlan::LineDriven)?
            .into_iter()
            .map(|hit| hit.frame_id)
            .collect();
        let mut by_frames: Vec<i64> = store
            .search_with_plan(&params, SearchPlan::FrameScan)?
            .into_iter()
            .map(|hit| hit.frame_id)
            .collect();
        by_lines.sort_unstable();
        by_frames.sort_unstable();
        assert!(!by_lines.is_empty(), "{word} must be found");
        assert_eq!(by_lines, by_frames, "{word}");
    }
    Ok(())
}

#[test]
fn a_search_hit_marks_where_its_matched_lines_sit() -> TestResult {
    let (_dir, store) = open()?;
    insert(&store, 0, &["intro", "the needle line", "outro"])?;
    let hits = store.search(&search_params("\"needle\"", 5))?;
    assert_eq!(hits.len(), 1);
    let lines = &hits[0].matched_lines;
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0].text, "the needle line");
    assert_eq!((lines[0].x, lines[0].y), (100, 300));
    Ok(())
}

#[test]
fn erasing_returns_the_freed_pages_to_the_file_system() -> TestResult {
    let (dir, store) = open()?;
    let text: Vec<String> = (0..200)
        .map(|index| format!("filler line number {index} {}", "x".repeat(60)))
        .collect();
    let lines: Vec<&str> = text.iter().map(String::as_str).collect();
    for slot in 0..40 {
        insert(&store, slot, &lines)?;
    }
    store.erase_range(0, 40 * FRAME_SPACING_MS)?;
    let connection = Connection::open(dir.path().join("erst.sqlite"))?;
    let free: i64 = connection.pragma_query_value(None, "freelist_count", |row| row.get(0))?;
    assert_eq!(free, 0, "every freed page must go back to the file system");
    Ok(())
}
