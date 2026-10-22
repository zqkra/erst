//! Migrations from earlier schema versions, and open errors that name a path.

use std::error::Error;
use std::fs;
use std::path::Path;

use erst_store::{LineSource, NewFrame, NewLine, SearchParams, Store, StoreError};
use rusqlite::Connection;

type TestResult = Result<(), Box<dyn Error + Send + Sync>>;

const V1_INIT: &str = include_str!("../migrations/0001_init.sql");
const V2_SECURE_DELETE: &str = include_str!("../migrations/0002_secure_delete.sql");
const V3_PENDING_UNLINKS: &str = include_str!("../migrations/0003_pending_unlinks.sql");
const V4_LINE_SOURCES: &str = include_str!("../migrations/0004_line_sources.sql");

fn search_params(fts_match: &str) -> SearchParams {
    SearchParams {
        fts_match: fts_match.to_owned(),
        app: None,
        since_ms: None,
        until_ms: None,
        limit: 10,
    }
}

fn create_version_two_database(path: &Path) -> TestResult {
    let connection = Connection::open(path)?;
    connection.pragma_update(None, "auto_vacuum", "INCREMENTAL")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    connection.execute_batch(V1_INIT)?;
    connection.execute_batch(V2_SECURE_DELETE)?;
    connection.pragma_update(None, "user_version", 2)?;
    connection.execute_batch(
        "
        INSERT INTO apps (id, bundle_id, name) VALUES (1, 'com.example.App', 'Example');
        INSERT INTO segments (id, path, started_at, ended_at, width, height, bytes)
        VALUES (1, 'segments/v2.mp4', 0, 1000, 1920, 1080, 10);
        INSERT INTO frames (id, captured_at, segment_id, pts_ms, app_id, window_title, change_ratio)
        VALUES (1, 500, 1, 0, 1, 'Window', 0.5);
        INSERT INTO text_lines (id, hash, text)
        VALUES (1, X'00000000000000000000000000000001', 'V2LEGACYTOKEN');
        INSERT INTO frame_lines (frame_id, line_id, x, y, w, h) VALUES (1, 1, 10, 20, 30, 40);
        ",
    )?;
    Ok(())
}

/// A version 3 database: the version 2 rows plus the pending unlink queue and
/// the wider `frame_lines` key. Its lines predate the source column.
fn create_version_three_database(path: &Path) -> TestResult {
    create_version_two_database(path)?;
    let connection = Connection::open(path)?;
    connection.execute_batch(V3_PENDING_UNLINKS)?;
    connection.pragma_update(None, "user_version", 3)?;
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

fn table_exists(connection: &Connection, name: &str) -> Result<bool, rusqlite::Error> {
    connection.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
        [name],
        |row| row.get::<_, i64>(0).map(|count| count == 1),
    )
}

#[test]
fn a_new_database_is_at_version_five_with_packed_layouts() -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("fresh.sqlite");
    drop(Store::open(&path)?);

    let connection = Connection::open(&path)?;
    let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    assert_eq!(version, 5);
    assert!(table_exists(&connection, "pending_unlinks")?);
    assert!(table_exists(&connection, "frame_text")?);
    assert!(table_exists(&connection, "line_runs")?);
    assert!(!table_exists(&connection, "frame_lines")?);
    Ok(())
}

#[test]
fn a_version_three_database_migrates_with_its_lines_read_as_ocr() -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("erst.sqlite");
    create_version_three_database(&path)?;

    let store = Store::open(&path)?;
    let detail = store.frame_detail(1)?;
    assert_eq!(detail.lines.len(), 1);
    assert_eq!(detail.lines[0].text, "V2LEGACYTOKEN");
    assert_eq!(detail.lines[0].source, LineSource::Ocr);

    let connection = Connection::open(&path)?;
    let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    assert_eq!(version, 5);
    Ok(())
}

#[test]
fn a_version_two_database_migrates_with_its_rows_and_the_wider_key() -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("erst.sqlite");
    create_version_two_database(&path)?;

    let store = Store::open(&path)?;
    let detail = store.frame_detail(1)?;
    assert_eq!(detail.lines.len(), 1);
    assert_eq!(detail.lines[0].text, "V2LEGACYTOKEN");
    assert_eq!(store.search(&search_params("\"V2LEGACYTOKEN\""))?.len(), 1);

    // The rebuilt table accepts two identical boxes on one row.
    let segment = store.begin_segment("segments/v3.mp4", 2_000, 1920, 1080)?;
    let frame_id = store.insert_frame(&NewFrame {
        captured_at: 2_500,
        segment_id: segment,
        pts_ms: 0,
        bundle_id: "com.example.App".to_owned(),
        app_name: "Example".to_owned(),
        window_title: Some("Window".to_owned()),
        url: None,
        change_ratio: 0.1,
        lines: vec![
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
    })?;
    assert_eq!(store.frame_detail(frame_id)?.lines.len(), 2);

    // The old rows now live in packed layouts and runs, and the version is current.
    let connection = Connection::open(&path)?;
    let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    assert_eq!(version, 5);
    assert!(!table_exists(&connection, "frame_lines")?);
    let layouts: i64 =
        connection.query_row("SELECT COUNT(*) FROM frame_text", [], |row| row.get(0))?;
    assert_eq!(layouts, 2);
    let legacy_runs: i64 = connection.query_row(
        "SELECT COUNT(*) FROM line_runs WHERE line_id = 1 AND first_frame = 1 AND last_frame = 1",
        [],
        |row| row.get(0),
    )?;
    assert_eq!(legacy_runs, 1);

    // Erasing migrated data leaves nothing behind in either file.
    let outcome = store.erase_range(0, 1_000)?;
    assert_eq!(outcome.frames_removed, 1);
    assert!(outcome.purge_complete);
    assert_absent(&path, b"V2LEGACYTOKEN")?;
    assert_absent(&path.with_extension("sqlite-wal"), b"V2LEGACYTOKEN")?;
    Ok(())
}

/// A version 4 database with six frames. Line 1 shows on frames 1 to 3 and 5
/// to 6; frame 4 shows only line 2, which runs from frame 2 to 4; frame 6 shows
/// line 1 twice, at two spots, from the accessibility tree.
fn create_version_four_database(path: &Path) -> TestResult {
    create_version_three_database(path)?;
    let connection = Connection::open(path)?;
    connection.execute_batch(V4_LINE_SOURCES)?;
    connection.pragma_update(None, "user_version", 4)?;
    connection.execute_batch(
        "
        INSERT INTO text_lines (id, hash, text)
        VALUES (2, X'00000000000000000000000000000002', 'SECONDLINE');
        INSERT INTO frames (id, captured_at, segment_id, pts_ms, app_id, window_title, change_ratio)
        VALUES (2, 510, 1, 10, 1, 'Window', 0.5), (3, 520, 1, 20, 1, 'Window', 0.5),
               (4, 530, 1, 30, 1, 'Window', 0.5), (5, 540, 1, 40, 1, 'Window', 0.5),
               (6, 550, 1, 50, 1, 'Window', 0.5);
        INSERT INTO frame_lines (frame_id, line_id, x, y, w, h, source) VALUES
            (2, 1, 10, 20, 30, 40, 0), (2, 2, 10, 900, 30, 40, 0),
            (3, 1, 10, 20, 30, 40, 0), (3, 2, 10, 900, 30, 40, 0),
            (4, 2, 10, 900, 30, 40, 0),
            (5, 1, 10, 20, 30, 40, 0),
            (6, 1, 10, 20, 30, 40, 1), (6, 1, 5000, 7000, 30, 40, 1);
        ",
    )?;
    Ok(())
}

#[test]
fn a_version_four_database_packs_its_rows_into_layouts_and_runs() -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("erst.sqlite");
    create_version_four_database(&path)?;

    let store = Store::open(&path)?;
    let wal = fs::metadata(path.with_extension("sqlite-wal")).map_or(0, |metadata| metadata.len());
    assert_eq!(wal, 0, "the migration's WAL must be given back");
    let connection = Connection::open(&path)?;
    let mut statement = connection.prepare(
        "SELECT line_id, first_frame, last_frame FROM line_runs ORDER BY line_id, first_frame",
    )?;
    let runs: Vec<(i64, i64, i64)> = statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
        .collect::<Result<_, _>>()?;
    assert_eq!(runs, vec![(1, 1, 3), (1, 5, 6), (2, 2, 4)]);

    let third = store.frame_detail(3)?;
    let third: Vec<(&str, u16, u16)> = third
        .lines
        .iter()
        .map(|line| (line.text.as_str(), line.x, line.y))
        .collect();
    assert_eq!(
        third,
        vec![("V2LEGACYTOKEN", 10, 20), ("SECONDLINE", 10, 900)]
    );

    let sixth = store.frame_detail(6)?;
    assert_eq!(sixth.lines.len(), 2);
    assert!(
        sixth
            .lines
            .iter()
            .all(|line| line.source == LineSource::Accessibility)
    );
    assert_eq!((sixth.lines[1].x, sixth.lines[1].y), (5000, 7000));

    let mut frames: Vec<i64> = store
        .search(&search_params("\"SECONDLINE\""))?
        .into_iter()
        .map(|hit| hit.frame_id)
        .collect();
    frames.sort_unstable();
    assert_eq!(
        frames.len(),
        1,
        "frames 2 to 4 are seconds apart, so they are one moment"
    );
    Ok(())
}

#[test]
fn open_names_the_directory_it_could_not_create() -> TestResult {
    let dir = tempfile::tempdir()?;
    let blocker = dir.path().join("blocker");
    fs::write(&blocker, b"not a directory")?;
    let path = blocker.join("erst.sqlite");

    let Err(StoreError::CreateDirectory { path: reported, .. }) = Store::open(&path) else {
        panic!("expected a directory error for {}", path.display());
    };
    assert_eq!(reported, blocker);
    Ok(())
}

#[test]
fn open_read_only_names_the_database_it_could_not_open() -> TestResult {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("missing.sqlite");

    let Err(StoreError::OpenDatabase { path: reported, .. }) = Store::open_read_only(&path) else {
        panic!("expected an open error for {}", path.display());
    };
    assert_eq!(reported, path);
    Ok(())
}
