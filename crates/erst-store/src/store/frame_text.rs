//! Where each frame's lines sit, and which frames hold each line.
//!
//! `frame_text` keeps one packed layout per frame (see [`super::layout`]).
//! `line_runs` lets search go from a line to its frames: a run `(line, first,
//! last)` says every frame with an id in `first..=last` shows the line. A line
//! usually stays on screen across many frames, so one run replaces many rows.
//!
//! Runs keep two invariants. Every existing frame inside a run shows its line,
//! and both ends of a run are frames that exist. New frames always take an id
//! above every existing one, so they can never land inside an older run.
//! Deleting frames keeps the first invariant by itself; [`trim_runs`] restores
//! the second.

use std::collections::HashMap;

use rusqlite::{Connection, OptionalExtension, params, params_from_iter};

use crate::error::StoreError;
use crate::model::LineBox;
use crate::store::layout::{self, Placement};
use crate::store::placeholders;

/// SQLite's default maximum is 32766 variables; chunks stay well below it.
const MAX_IDS_PER_QUERY: usize = 500;

const INSERT_LAYOUT: &str = "INSERT INTO frame_text (frame_id, layout) VALUES (?1, ?2)";

const SELECT_PREVIOUS_FRAME: &str = "SELECT MAX(id) FROM frames WHERE id < ?1";

/// Grows the line's latest run when it ends at the frame just before this one.
const EXTEND_RUN: &str = "
    UPDATE line_runs SET last_frame = ?3
    WHERE line_id = ?1 AND last_frame = ?2
      AND first_frame = (SELECT MAX(first_frame) FROM line_runs WHERE line_id = ?1)";

const START_RUN: &str =
    "INSERT INTO line_runs (line_id, first_frame, last_frame) VALUES (?1, ?2, ?2)";

/// A run whose frames are all gone holds nothing.
const DELETE_EMPTY_RUNS: &str = "
    DELETE FROM line_runs
    WHERE line_id IN (SELECT id FROM erased_lines)
      AND NOT EXISTS (
          SELECT 1 FROM frames f WHERE f.id BETWEEN line_runs.first_frame AND line_runs.last_frame
      )";

/// Pulls both ends of a run in to the nearest frames that still exist.
const TRIM_RUN_ENDS: &str = "
    UPDATE line_runs SET
        first_frame = (SELECT MIN(f.id) FROM frames f
                       WHERE f.id BETWEEN line_runs.first_frame AND line_runs.last_frame),
        last_frame = (SELECT MAX(f.id) FROM frames f
                      WHERE f.id BETWEEN line_runs.first_frame AND line_runs.last_frame)
    WHERE line_id IN (SELECT id FROM erased_lines)";

/// Stores a new frame's layout and extends or starts the run of each line on it.
///
/// `frame_id` must be the newest frame, which every insert is, because SQLite
/// gives a new row an id above every existing one.
pub(crate) fn write(
    connection: &Connection,
    frame_id: i64,
    placements: Vec<Placement>,
) -> Result<(), StoreError> {
    if placements.is_empty() {
        return Ok(());
    }
    let mut line_ids: Vec<i64> = placements
        .iter()
        .map(|placement| placement.line_id)
        .collect();
    line_ids.sort_unstable();
    line_ids.dedup();
    connection
        .prepare_cached(INSERT_LAYOUT)?
        .execute(params![frame_id, layout::encode(placements)])?;
    let previous: Option<i64> = connection
        .prepare_cached(SELECT_PREVIOUS_FRAME)?
        .query_row([frame_id], |row| row.get(0))?;
    let mut extend = connection.prepare_cached(EXTEND_RUN)?;
    let mut start = connection.prepare_cached(START_RUN)?;
    for line_id in line_ids {
        let extended = match previous {
            Some(previous) => extend.execute(params![line_id, previous, frame_id])?,
            None => 0,
        };
        if extended == 0 {
            start.execute(params![line_id, frame_id])?;
        }
    }
    Ok(())
}

/// The layouts of the given frames. A frame with no lines has no entry.
pub(crate) fn layouts(
    connection: &Connection,
    frame_ids: &[i64],
) -> Result<HashMap<i64, Vec<Placement>>, StoreError> {
    let mut layouts = HashMap::with_capacity(frame_ids.len());
    for chunk in frame_ids.chunks(MAX_IDS_PER_QUERY) {
        let sql = format!(
            "SELECT frame_id, layout FROM frame_text WHERE frame_id IN ({})",
            placeholders(chunk.len())
        );
        let mut statement = connection.prepare_cached(&sql)?;
        let mut rows = statement.query(params_from_iter(chunk.iter().copied()))?;
        while let Some(row) = rows.next()? {
            let bytes: Vec<u8> = row.get(1)?;
            layouts.insert(row.get(0)?, layout::decode(&bytes)?);
        }
    }
    Ok(layouts)
}

/// One frame's layout, empty when the frame has no lines.
pub(crate) fn layout_of(
    connection: &Connection,
    frame_id: i64,
) -> Result<Vec<Placement>, StoreError> {
    let bytes: Option<Vec<u8>> = connection
        .prepare_cached("SELECT layout FROM frame_text WHERE frame_id = ?1")?
        .query_row([frame_id], |row| row.get(0))
        .optional()?;
    bytes.map_or_else(|| Ok(Vec::new()), |bytes| layout::decode(&bytes))
}

/// The text of each line id.
pub(crate) fn texts(
    connection: &Connection,
    line_ids: impl IntoIterator<Item = i64>,
) -> Result<HashMap<i64, String>, StoreError> {
    let mut ids: Vec<i64> = line_ids.into_iter().collect();
    ids.sort_unstable();
    ids.dedup();
    let mut texts = HashMap::with_capacity(ids.len());
    for chunk in ids.chunks(MAX_IDS_PER_QUERY) {
        let sql = format!(
            "SELECT id, text FROM text_lines WHERE id IN ({})",
            placeholders(chunk.len())
        );
        let mut statement = connection.prepare_cached(&sql)?;
        let rows = statement.query_map(params_from_iter(chunk.iter().copied()), |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (id, text) = row?;
            texts.insert(id, text);
        }
    }
    Ok(texts)
}

/// Placements with their text, top to bottom, the way readers return lines.
pub(crate) fn line_boxes(placements: &[Placement], texts: &HashMap<i64, String>) -> Vec<LineBox> {
    placements
        .iter()
        .filter_map(|placement| {
            Some(LineBox {
                text: texts.get(&placement.line_id)?.clone(),
                x: placement.x,
                y: placement.y,
                w: placement.w,
                h: placement.h,
                source: placement.source,
            })
        })
        .collect()
}

/// Stages every line the frames in `erased_frames` show, before they are
/// deleted, so [`trim_runs`] and the orphan sweep only touch those lines.
pub(crate) fn stage_erased_lines(connection: &Connection) -> Result<(), StoreError> {
    let frame_ids: Vec<i64> = {
        let mut statement = connection.prepare_cached("SELECT id FROM erased_frames")?;
        let rows = statement.query_map([], |row| row.get(0))?;
        rows.collect::<Result<_, _>>()?
    };
    let mut insert =
        connection.prepare_cached("INSERT OR IGNORE INTO erased_lines (id) VALUES (?1)")?;
    for placements in layouts(connection, &frame_ids)?.values() {
        for placement in placements {
            insert.execute([placement.line_id])?;
        }
    }
    Ok(())
}

/// Restores the run invariants after frames were deleted: runs with no frame
/// left go, and the rest end on frames that exist.
pub(crate) fn trim_runs(connection: &Connection) -> Result<(), StoreError> {
    connection.execute(DELETE_EMPTY_RUNS, [])?;
    connection.execute(TRIM_RUN_ENDS, [])?;
    Ok(())
}
