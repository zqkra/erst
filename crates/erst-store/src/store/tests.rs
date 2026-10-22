//! Store-level tests that need the private connections.

use std::error::Error;
use std::sync::Mutex;

use rusqlite::{Connection, OpenFlags, params};
use tempfile::TempDir;

use super::Store;
use crate::error::StoreError;
use crate::model::{LineSource, NewFrame, NewLine, SearchParams};
use crate::schema;

fn open_store() -> Result<(TempDir, Store), Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let store = Store::open(&dir.path().join("erst.sqlite"))?;
    Ok((dir, store))
}

fn frame(segment_id: i64, lines: Vec<NewLine>) -> NewFrame {
    NewFrame {
        captured_at: 1_000,
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

fn line(text: &str, index: u16) -> NewLine {
    NewLine {
        text: text.to_owned(),
        x: 100,
        y: 100 + index * 200,
        w: 1_000,
        h: 100,
        source: LineSource::Ocr,
    }
}

fn lock_error() -> std::io::Error {
    std::io::Error::other("lock poisoned")
}

fn search_one(store: &Store, fts_match: &str) -> Result<Vec<crate::model::SearchHit>, StoreError> {
    store.search(&SearchParams {
        fts_match: fts_match.to_owned(),
        app: None,
        since_ms: None,
        until_ms: None,
        limit: 10,
    })
}

#[test]
fn migrations_are_idempotent_and_set_version() -> Result<(), Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("nested/erst.sqlite");
    {
        let store = Store::open(&path)?;
        let reader = store.reader.lock().map_err(|_| lock_error())?;
        let version: u32 = reader.pragma_query_value(None, "user_version", |row| row.get(0))?;
        assert_eq!(version, schema::LATEST_VERSION);
        let auto_vacuum: i64 = reader.pragma_query_value(None, "auto_vacuum", |row| row.get(0))?;
        // 2 is INCREMENTAL; the pragma only takes effect before the first table.
        assert_eq!(auto_vacuum, 2);
    }
    {
        let store = Store::open(&path)?;
        let reader = store.reader.lock().map_err(|_| lock_error())?;
        let version: u32 = reader.pragma_query_value(None, "user_version", |row| row.get(0))?;
        assert_eq!(version, schema::LATEST_VERSION);
    }
    Ok(())
}

#[test]
fn read_only_open_rejects_a_schema_behind_the_build() -> Result<(), Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("empty.sqlite");
    Connection::open(&path)?;
    let result = Store::open_read_only(&path);
    assert!(matches!(
        result,
        Err(StoreError::SchemaTooOld {
            found: 0,
            expected: schema::LATEST_VERSION
        })
    ));
    Ok(())
}

#[test]
fn read_only_sqlite_errors_map_to_read_only() -> Result<(), Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("erst.sqlite");
    drop(Store::open(&path)?);
    let connection = Connection::open_with_flags(
        &path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    match connection.execute("CREATE TABLE not_allowed (id INTEGER)", []) {
        Ok(_) => panic!("read-only connection must reject DDL"),
        Err(error) => assert!(matches!(StoreError::from(error), StoreError::ReadOnly)),
    }
    Ok(())
}

#[test]
fn deleting_a_frame_cascades_its_layout() -> Result<(), Box<dyn Error>> {
    let (_dir, store) = open_store()?;
    let segment_id = store.begin_segment("segments/a.mp4", 1, 1920, 1080)?;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        vec![line("first line", 0), line("second line", 1)],
    ))?;
    {
        let mut writer = store.writer.lock().map_err(|_| lock_error())?;
        let connection: &mut Connection = writer.as_mut().ok_or(lock_error())?;
        connection.execute("DELETE FROM frames WHERE id = ?1", [frame_id])?;
    }
    let reader = store.reader.lock().map_err(|_| lock_error())?;
    let layouts: i64 = reader.query_row(
        "SELECT COUNT(*) FROM frame_text WHERE frame_id = ?1",
        [frame_id],
        |row| row.get(0),
    )?;
    let text_lines: i64 =
        reader.query_row("SELECT COUNT(*) FROM text_lines", [], |row| row.get(0))?;
    assert_eq!(layouts, 0);
    // Two frame lines and the frame's window title, which is a line too.
    assert_eq!(text_lines, 3);
    Ok(())
}

#[test]
fn fts_triggers_track_insert_update_and_delete() -> Result<(), Box<dyn Error>> {
    let (_dir, store) = open_store()?;
    let segment_id = store.begin_segment("segments/a.mp4", 1, 1920, 1080)?;
    let frame_id = store.insert_frame(&frame(segment_id, vec![line("triggerword", 0)]))?;
    assert_eq!(search_one(&store, "triggerword")?.len(), 1);

    {
        let writer = store.writer.lock().map_err(|_| lock_error())?;
        let connection = writer.as_ref().ok_or(lock_error())?;
        connection.execute(
            "UPDATE text_lines SET text = 'replacedword' WHERE text = 'triggerword'",
            [],
        )?;
    }
    assert_eq!(search_one(&store, "triggerword")?.len(), 0);
    assert_eq!(search_one(&store, "replacedword")?.len(), 1);

    {
        let writer = store.writer.lock().map_err(|_| lock_error())?;
        let connection = writer.as_ref().ok_or(lock_error())?;
        connection.execute("DELETE FROM frames WHERE id = ?1", [frame_id])?;
        // Runs reference their line, so they go first, as erase drops them first.
        connection.execute("DELETE FROM line_runs", [])?;
        connection.execute("DELETE FROM text_lines", [])?;
    }
    assert_eq!(search_one(&store, "replacedword")?.len(), 0);
    Ok(())
}

#[test]
fn last_span_before_reads_one_index_seek_without_a_sort() -> Result<(), Box<dyn Error>> {
    let (_dir, store) = open_store()?;
    let reader = store.reader.lock().map_err(|_| lock_error())?;
    let sql = format!(
        "EXPLAIN QUERY PLAN {}",
        super::reads::SELECT_LAST_SPAN_BEFORE
    );
    let mut statement = reader.prepare(&sql)?;
    let plan = statement
        .query_map(
            params!["com.example.App", Some("Window"), 1_000_i64],
            |row| row.get::<_, String>(3),
        )?
        .collect::<Result<Vec<_>, _>>()?;
    let plan = plan.join("\n");
    assert!(plan.contains("spans_app_started"), "{plan}");
    assert!(plan.contains("started_at<?"), "{plan}");
    assert!(!plan.contains("TEMP B-TREE"), "{plan}");
    assert!(!plan.contains("SCAN spans"), "{plan}");
    Ok(())
}

#[test]
fn store_is_send_and_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<Store>();
    assert_send_sync::<Mutex<Option<Connection>>>();
}
