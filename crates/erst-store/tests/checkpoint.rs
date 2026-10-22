//! A reader holding a snapshot keeps the WAL from truncating after a delete.

mod common;

use std::fs;
use std::path::Path;

use common::{TestResult, open_store};
use erst_store::{Store, StoreError};

const MINUTE_MS: i64 = 60_000;
const DAY: i64 = 1_700_000_000_000;

fn seed_erased_text(store: &Store) -> TestResult {
    let segment = store.begin_segment("segments/held.mp4", DAY, 1920, 1080)?;
    store.finish_segment(segment, DAY + 10 * MINUTE_MS, 1_000)?;
    store.insert_frame(&common::frame(
        segment,
        DAY + MINUTE_MS,
        common::APP,
        common::APP_NAME,
        Some(common::TITLE),
        vec![common::line("ZEBRAHELDTOKEN", 0)],
    ))?;
    Ok(())
}

fn assert_absent(path: &Path, needle: &[u8]) -> TestResult {
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

#[test]
fn erase_reports_an_incomplete_purge_while_a_reader_holds_a_snapshot() -> TestResult {
    let (dir, store) = open_store()?;
    seed_erased_text(&store)?;
    let database = dir.path().join("erst.sqlite");
    let wal = dir.path().join("erst.sqlite-wal");
    let reader = rusqlite::Connection::open(&database)?;
    reader.execute_batch("BEGIN; SELECT COUNT(*) FROM frames;")?;

    let outcome = store.erase_range(DAY, DAY + 10 * MINUTE_MS)?;
    // The rows and the unlink are durable even though the WAL did not truncate.
    assert_eq!(outcome.frames_removed, 1);
    assert!(!outcome.purge_complete);
    assert_eq!(outcome.segment_paths, vec!["segments/held.mp4".to_owned()]);
    assert_eq!(
        store.pending_unlinks()?,
        vec!["segments/held.mp4".to_owned()]
    );

    // Once the reader lets go, repeating the erase completes the purge.
    reader.execute_batch("COMMIT")?;
    let retry = store.erase_range(DAY, DAY + 10 * MINUTE_MS)?;
    assert!(retry.purge_complete);
    assert_eq!(retry.frames_removed, 0);
    assert_absent(&database, b"ZEBRAHELDTOKEN")?;
    assert_absent(&wal, b"ZEBRAHELDTOKEN")?;
    assert_eq!(fs::metadata(&wal).map_or(0, |meta| meta.len()), 0);
    Ok(())
}

#[test]
fn delete_segment_reports_a_busy_checkpoint_and_keeps_the_path_queued() -> TestResult {
    let (dir, store) = open_store()?;
    seed_erased_text(&store)?;
    let segment = store
        .segments()?
        .first()
        .ok_or("seeded segment missing")?
        .id;
    let database = dir.path().join("erst.sqlite");
    let reader = rusqlite::Connection::open(&database)?;
    reader.execute_batch("BEGIN; SELECT COUNT(*) FROM frames;")?;

    let result = store.delete_segment(segment);
    reader.execute_batch("COMMIT")?;

    assert!(matches!(result, Err(StoreError::CheckpointBusy)));
    assert_eq!(store.segments()?, Vec::new());
    assert_eq!(
        store.pending_unlinks()?,
        vec!["segments/held.mp4".to_owned()]
    );
    Ok(())
}
