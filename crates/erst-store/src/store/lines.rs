//! Deduplicated text lines for a new frame.
//!
//! Consecutive frames share most of their text, so each distinct line is stored
//! once in `text_lines`, keyed by the hash of its normalized text, and frames
//! reference it from their packed layout in `frame_text`.

use std::collections::{HashMap, HashSet};

use rusqlite::{Connection, params, params_from_iter};

use crate::error::StoreError;
use crate::model::NewLine;
use crate::normalize::{line_hash, normalize_text};
use crate::store::frame_text;
use crate::store::layout::Placement;
use crate::store::placeholders;

/// Hash lookups stay well below SQLite's variable limit, which is 32766 by
/// default.
const MAX_HASHES_PER_LOOKUP: usize = 400;

const INSERT_LINE: &str = "
    INSERT INTO text_lines (hash, text) VALUES (?1, ?2)
    ON CONFLICT(hash) DO NOTHING";

const SELECT_LINE_ID: &str = "SELECT id FROM text_lines WHERE hash = ?1";

/// A frame line with its normalized text and content hash.
struct PreparedLine<'a> {
    line: &'a NewLine,
    hash: [u8; 16],
    text: String,
}

/// Trims and collapses every line, dropping the ones that are only whitespace.
fn prepare_lines<'a>(lines: impl IntoIterator<Item = &'a NewLine>) -> Vec<PreparedLine<'a>> {
    lines
        .into_iter()
        .filter_map(|line| {
            let text = normalize_text(&line.text);
            if text.is_empty() {
                return None;
            }
            Some(PreparedLine {
                line,
                hash: line_hash(&text),
                text,
            })
        })
        .collect()
}

/// Looks up every distinct hash of one frame in a single statement per chunk.
/// Most lines repeat between frames, so this replaces a per-line insert round
/// trip with one read.
fn existing_line_ids(
    connection: &Connection,
    lines: &[PreparedLine<'_>],
) -> Result<HashMap<[u8; 16], i64>, StoreError> {
    let mut seen = HashSet::with_capacity(lines.len());
    let hashes: Vec<&[u8]> = lines
        .iter()
        .filter(|line| seen.insert(line.hash))
        .map(|line| line.hash.as_slice())
        .collect();
    let mut ids = HashMap::with_capacity(hashes.len());
    for chunk in hashes.chunks(MAX_HASHES_PER_LOOKUP) {
        let sql = format!(
            "SELECT hash, id FROM text_lines WHERE hash IN ({})",
            placeholders(chunk.len())
        );
        let mut statement = connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(chunk.iter().copied()), |row| {
            Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, i64>(1)?))
        })?;
        for row in rows {
            let (hash, id) = row?;
            if let Ok(hash) = <[u8; 16]>::try_from(hash.as_slice()) {
                ids.insert(hash, id);
            }
        }
    }
    Ok(ids)
}

/// Stores the lines of one frame and their positions, inside the frame's
/// transaction.
pub(crate) fn insert_frame_lines<'a>(
    connection: &Connection,
    frame_id: i64,
    input: impl IntoIterator<Item = &'a NewLine>,
) -> Result<(), StoreError> {
    let lines = prepare_lines(input);
    let mut line_ids = existing_line_ids(connection, &lines)?;
    let mut insert_line = connection.prepare_cached(INSERT_LINE)?;
    let mut select_line = connection.prepare_cached(SELECT_LINE_ID)?;
    let mut placements = Vec::with_capacity(lines.len());
    for PreparedLine { line, hash, text } in lines {
        let line_id = if let Some(&line_id) = line_ids.get(&hash) {
            line_id
        } else {
            // The conflict clause keeps this safe if another writer stored the
            // same text after the lookup.
            insert_line.execute(params![hash.as_slice(), text])?;
            let line_id: i64 = select_line.query_row([hash.as_slice()], |row| row.get(0))?;
            line_ids.insert(hash, line_id);
            line_id
        };
        placements.push(Placement {
            line_id,
            x: line.x,
            y: line.y,
            w: line.w,
            h: line.h,
            source: line.source,
        });
    }
    frame_text::write(connection, frame_id, placements)
}
