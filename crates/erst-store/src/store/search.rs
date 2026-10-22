//! Full-text search and moment grouping.

use std::collections::HashMap;

use rusqlite::{Connection, Row, params};

use crate::error::StoreError;
use crate::model::{LineBox, SearchHit, SearchParams, SearchPlan};
use crate::store::layout::Placement;
use crate::store::{Store, frame_text};

/// Frames less than ten minutes apart join one moment.
const MOMENT_GAP_MS: i64 = 600_000;

/// Candidate frames fetched per requested hit before the next page.
const CANDIDATE_ROWS_PER_HIT: i64 = 25;

/// Hard cap on one candidate page. Paging keeps a long session from filling
/// the window and hiding older moments, and the cap keeps one page bounded even
/// when the caller asks for a large limit.
const MAX_CANDIDATE_PAGE_ROWS: i64 = 500;

/// A frame-scan page that finds no match grows by this factor, up to
/// [`MAX_FRAME_SCAN_PAGE_ROWS`]. Sparse terms still scan the same rows, just in
/// fewer round trips, while common terms keep the small first page.
const FRAME_SCAN_PAGE_GROWTH: i64 = 4;

/// Upper bound for one frame-scan page after growth.
const MAX_FRAME_SCAN_PAGE_ROWS: i64 = 10_000;

/// At or above this many matched lines the frame scan replaces the line plan.
///
/// The line plan walks every matched line and then deduplicates and sorts the
/// frames that hold them, so its cost grows with the match count. The frame scan
/// walks the newest frames and checks their few line ids against the matched
/// set, so it stops as soon as it has enough moments. Both plans are measured in
/// `examples/bench_store.rs` over 1,000,000 lines. The line plan is still under
/// the 50 ms budget at 20,000 matches and over it at 79,000, so the switch keeps
/// medium terms on the line plan with headroom for slower machines while
/// keeping rare terms off a scan through months of frames.
const LINE_PLAN_MAX_MATCHED_LINES: usize = 20_000;

/// Plan choice only needs to know which side of the threshold the match count
/// falls on, so this stops one row past it instead of materializing every id.
const SELECT_MATCHED_LINE_IDS_CAPPED: &str = "
    SELECT rowid FROM text_lines_fts
    WHERE text_lines_fts MATCH ?1
    LIMIT ?2";

/// The full id list is ordered by rowid so membership is a binary search
/// instead of a hash lookup over a set built before the plan is known.
const SELECT_MATCHED_LINE_IDS: &str = "
    SELECT rowid FROM text_lines_fts
    WHERE text_lines_fts MATCH ?1
    ORDER BY rowid";

/// Common terms: walk frames newest first, then keep the page's frames whose
/// lines are in the matched set. The cursor bound makes each page a keyset
/// continuation of `(captured_at DESC, id DESC)`, so paging never re-reads
/// rows.
const FRAME_SCAN_PAGE_SQL: &str = "
    SELECT f.id, f.captured_at,
           COALESCE(a.bundle_id, ''), COALESCE(a.name, ''),
           f.window_title, f.url, s.path, f.pts_ms
    FROM frames f
    LEFT JOIN apps a ON a.id = f.app_id
    JOIN segments s ON s.id = f.segment_id
    WHERE (?1 IS NULL OR a.name = ?1 COLLATE NOCASE OR a.bundle_id = ?1 COLLATE NOCASE)
      AND (?2 IS NULL OR f.captured_at >= ?2)
      AND (?3 IS NULL OR f.captured_at < ?3)
      AND (?4 IS NULL OR f.captured_at < ?4 OR (f.captured_at = ?4 AND f.id < ?5))
    ORDER BY f.captured_at DESC, f.id DESC
    LIMIT ?6";

/// Rare terms: start from the matched lines and follow their `line_runs` to
/// the frames that hold them. The filters sit inside the materialized CTE so a
/// date or app filter shrinks the set before it is deduplicated and sorted. The
/// cursor keeps the next page strictly older than the last frame of this one.
const LINE_DRIVEN_PAGE_SQL: &str = "
    WITH matched(line_id) AS MATERIALIZED (
        SELECT rowid FROM text_lines_fts WHERE text_lines_fts MATCH ?1
    ),
    hit_frames(frame_id) AS MATERIALIZED (
        SELECT DISTINCT f.id
        FROM line_runs r
        JOIN frames f ON f.id BETWEEN r.first_frame AND r.last_frame
        LEFT JOIN apps a ON a.id = f.app_id
        WHERE r.line_id IN (SELECT line_id FROM matched)
          AND (?2 IS NULL OR a.name = ?2 COLLATE NOCASE OR a.bundle_id = ?2 COLLATE NOCASE)
          AND (?3 IS NULL OR f.captured_at >= ?3)
          AND (?4 IS NULL OR f.captured_at < ?4)
          AND (?5 IS NULL OR f.captured_at < ?5 OR (f.captured_at = ?5 AND f.id < ?6))
    )
    SELECT f.id, f.captured_at,
           COALESCE(a.bundle_id, ''), COALESCE(a.name, ''),
           f.window_title, f.url, s.path, f.pts_ms
    FROM hit_frames h
    JOIN frames f ON f.id = h.frame_id
    LEFT JOIN apps a ON a.id = f.app_id
    JOIN segments s ON s.id = f.segment_id
    ORDER BY f.captured_at DESC, f.id DESC
    LIMIT ?7";

struct Candidate {
    id: i64,
    captured_at: i64,
    bundle_id: String,
    app_name: String,
    window_title: Option<String>,
    url: Option<String>,
    segment_path: Option<String>,
    pts_ms: i64,
    matched_count: u64,
}

/// The last row of a candidate page, used as the keyset for the next page.
#[derive(Clone, Copy, PartialEq, Eq)]
struct FrameCursor {
    captured_at: i64,
    id: i64,
}

/// A moment while grouping. Candidates arrive newest first, so `oldest_ms` is
/// the timestamp of the previous candidate in this moment.
struct Moment {
    newest_ms: i64,
    oldest_ms: i64,
    representative: Candidate,
}

impl Store {
    /// Runs an FTS5 MATCH expression, groups matching frames into moments, and
    /// returns at most `limit` moments with the most recent first.
    pub fn search(&self, query: &SearchParams) -> Result<Vec<SearchHit>, StoreError> {
        self.search_with_plan(query, SearchPlan::Auto)
    }

    /// [`Store::search`] with an explicit access plan.
    ///
    /// [`SearchPlan::Auto`] is what production uses; the other arms exist so the
    /// benchmark can measure both plans on the same data.
    pub fn search_with_plan(
        &self,
        query: &SearchParams,
        plan: SearchPlan,
    ) -> Result<Vec<SearchHit>, StoreError> {
        if query.fts_match.trim().is_empty() || query.limit == 0 {
            return Ok(Vec::new());
        }
        let wanted = usize::try_from(query.limit).unwrap_or(usize::MAX);
        self.with_reader(|connection| {
            let plan = match plan {
                SearchPlan::Auto => auto_plan_for_query(connection, &query.fts_match)?,
                chosen => chosen,
            };
            let matched = matched_line_ids(connection, &query.fts_match)?;
            if matched.is_empty() {
                return Ok(Vec::new());
            }
            let page_size = candidate_page_size(query.limit);
            let mut frame_page_size = page_size;
            let mut moments: Vec<Moment> = Vec::new();
            let mut cursor: Option<FrameCursor> = None;
            loop {
                let (mut candidates, has_more) = if plan == SearchPlan::FrameScan {
                    frame_scan_page(connection, query, cursor, frame_page_size)?
                } else {
                    line_driven_page(connection, query, cursor, page_size)?
                };
                if candidates.is_empty() {
                    break;
                }
                let next_cursor = candidates.last().map(|candidate| FrameCursor {
                    captured_at: candidate.captured_at,
                    id: candidate.id,
                });
                attach_matched_counts(connection, &mut candidates, &matched)?;
                let mut found_match = true;
                if plan == SearchPlan::FrameScan {
                    found_match = candidates
                        .iter()
                        .any(|candidate| candidate.matched_count > 0);
                    candidates.retain(|candidate| candidate.matched_count > 0);
                }
                for candidate in candidates {
                    push_candidate(&mut moments, candidate);
                    if moments.len() > wanted {
                        break;
                    }
                }
                if moments.len() > wanted || !has_more || next_cursor == cursor {
                    break;
                }
                if plan == SearchPlan::FrameScan && !found_match {
                    frame_page_size = frame_page_size
                        .saturating_mul(FRAME_SCAN_PAGE_GROWTH)
                        .min(MAX_FRAME_SCAN_PAGE_ROWS);
                }
                cursor = next_cursor;
            }
            if moments.is_empty() {
                return Ok(Vec::new());
            }
            moments.truncate(wanted);
            let representative_ids: Vec<i64> = moments
                .iter()
                .map(|moment| moment.representative.id)
                .collect();
            let lines = matched_line_boxes(connection, &representative_ids, &matched)?;
            Ok(moments
                .into_iter()
                .map(|moment| build_hit(&moment, &lines))
                .collect())
        })
    }
}

fn auto_plan(matched_lines: usize) -> SearchPlan {
    if matched_lines < LINE_PLAN_MAX_MATCHED_LINES {
        SearchPlan::LineDriven
    } else {
        SearchPlan::FrameScan
    }
}

/// Counts matched lines up to one past the plan threshold. The row cap is what
/// keeps a term matching half of the index from costing a full id list before
/// the plan is chosen.
fn auto_plan_for_query(connection: &Connection, fts_match: &str) -> Result<SearchPlan, StoreError> {
    let cap = LINE_PLAN_MAX_MATCHED_LINES.saturating_add(1);
    let cap = i64::try_from(cap).unwrap_or(i64::MAX);
    let mut statement = connection.prepare_cached(SELECT_MATCHED_LINE_IDS_CAPPED)?;
    let mut rows = statement.query(params![fts_match, cap])?;
    let mut count = 0_usize;
    while rows.next()?.is_some() {
        count = count.saturating_add(1);
    }
    Ok(auto_plan(count))
}

/// The matched `text_lines` ids in rowid order. Membership checks are binary
/// searches over this slice.
fn matched_line_ids(connection: &Connection, fts_match: &str) -> Result<Vec<i64>, StoreError> {
    let mut statement = connection.prepare_cached(SELECT_MATCHED_LINE_IDS)?;
    let rows = statement.query_map([fts_match], |row| row.get(0))?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn is_matched(matched: &[i64], line_id: i64) -> bool {
    matched.binary_search(&line_id).is_ok()
}

fn candidate_page_size(limit: u32) -> i64 {
    i64::from(limit)
        .saturating_mul(CANDIDATE_ROWS_PER_HIT)
        .clamp(1, MAX_CANDIDATE_PAGE_ROWS)
}

fn cursor_bounds(cursor: Option<FrameCursor>) -> (Option<i64>, Option<i64>) {
    cursor.map_or((None, None), |cursor| {
        (Some(cursor.captured_at), Some(cursor.id))
    })
}

fn read_candidate(row: &Row<'_>) -> rusqlite::Result<Candidate> {
    Ok(Candidate {
        id: row.get(0)?,
        captured_at: row.get(1)?,
        bundle_id: row.get(2)?,
        app_name: row.get(3)?,
        window_title: row.get(4)?,
        url: row.get(5)?,
        segment_path: row.get(6)?,
        pts_ms: row.get(7)?,
        matched_count: 0,
    })
}

fn frame_scan_page(
    connection: &Connection,
    query: &SearchParams,
    cursor: Option<FrameCursor>,
    limit: i64,
) -> Result<(Vec<Candidate>, bool), StoreError> {
    let (cursor_at, cursor_id) = cursor_bounds(cursor);
    let mut statement = connection.prepare_cached(FRAME_SCAN_PAGE_SQL)?;
    let rows = statement.query_map(
        params![
            query.app,
            query.since_ms,
            query.until_ms,
            cursor_at,
            cursor_id,
            limit
        ],
        read_candidate,
    )?;
    let candidates = rows.collect::<Result<Vec<_>, _>>()?;
    let has_more = i64::try_from(candidates.len()).unwrap_or(i64::MAX) == limit;
    Ok((candidates, has_more))
}

fn line_driven_page(
    connection: &Connection,
    query: &SearchParams,
    cursor: Option<FrameCursor>,
    limit: i64,
) -> Result<(Vec<Candidate>, bool), StoreError> {
    let (cursor_at, cursor_id) = cursor_bounds(cursor);
    let mut statement = connection.prepare_cached(LINE_DRIVEN_PAGE_SQL)?;
    let rows = statement.query_map(
        params![
            query.fts_match,
            query.app,
            query.since_ms,
            query.until_ms,
            cursor_at,
            cursor_id,
            limit
        ],
        read_candidate,
    )?;
    let candidates = rows.collect::<Result<Vec<_>, _>>()?;
    let has_more = i64::try_from(candidates.len()).unwrap_or(i64::MAX) == limit;
    Ok((candidates, has_more))
}

/// Fills `matched_count` for every frame of one candidate page: the placements
/// of matched lines in its layout.
fn attach_matched_counts(
    connection: &Connection,
    candidates: &mut [Candidate],
    matched: &[i64],
) -> Result<(), StoreError> {
    if candidates.is_empty() {
        return Ok(());
    }
    let frame_ids: Vec<i64> = candidates.iter().map(|candidate| candidate.id).collect();
    let layouts = frame_text::layouts(connection, &frame_ids)?;
    for candidate in candidates {
        candidate.matched_count = layouts.get(&candidate.id).map_or(0, |placements| {
            placements
                .iter()
                .filter(|placement| is_matched(matched, placement.line_id))
                .count() as u64
        });
    }
    Ok(())
}

/// Matched lines of the representative frames, ordered by `y` then `x`.
///
/// Titles are matched too, so a word that only appears in a window title still
/// finds the frame. Each line keeps its `source`.
fn matched_line_boxes(
    connection: &Connection,
    frame_ids: &[i64],
    matched: &[i64],
) -> Result<HashMap<i64, Vec<LineBox>>, StoreError> {
    let matched_layouts: HashMap<i64, Vec<Placement>> = frame_text::layouts(connection, frame_ids)?
        .into_iter()
        .map(|(frame_id, placements)| {
            let kept = placements
                .into_iter()
                .filter(|placement| is_matched(matched, placement.line_id))
                .collect();
            (frame_id, kept)
        })
        .collect();
    let texts = frame_text::texts(
        connection,
        matched_layouts
            .values()
            .flatten()
            .map(|placement| placement.line_id),
    )?;
    Ok(matched_layouts
        .into_iter()
        .map(|(frame_id, placements)| (frame_id, frame_text::line_boxes(&placements, &texts)))
        .filter(|(_, lines)| !lines.is_empty())
        .collect())
}

fn push_candidate(moments: &mut Vec<Moment>, candidate: Candidate) {
    let joins = moments.last().is_some_and(|moment| {
        moment.representative.bundle_id == candidate.bundle_id
            && moment.representative.window_title == candidate.window_title
            && moment.oldest_ms.saturating_sub(candidate.captured_at) < MOMENT_GAP_MS
    });
    if joins {
        if let Some(moment) = moments.last_mut() {
            moment.oldest_ms = candidate.captured_at;
            if is_better(&candidate, &moment.representative) {
                moment.representative = candidate;
            }
        }
    } else {
        moments.push(Moment {
            newest_ms: candidate.captured_at,
            oldest_ms: candidate.captured_at,
            representative: candidate,
        });
    }
}

/// Representative is the frame with the most matched lines; ties go to the
/// most recent frame.
fn is_better(candidate: &Candidate, current: &Candidate) -> bool {
    (candidate.matched_count, candidate.captured_at, candidate.id)
        > (current.matched_count, current.captured_at, current.id)
}

fn build_hit(moment: &Moment, lines: &HashMap<i64, Vec<LineBox>>) -> SearchHit {
    let candidate = &moment.representative;
    SearchHit {
        frame_id: candidate.id,
        captured_at: candidate.captured_at,
        first_seen_ms: moment.oldest_ms,
        last_seen_ms: moment.newest_ms,
        bundle_id: candidate.bundle_id.clone(),
        app_name: candidate.app_name.clone(),
        window_title: candidate.window_title.clone(),
        url: candidate.url.clone(),
        segment_path: candidate.segment_path.clone(),
        pts_ms: candidate.pts_ms,
        matched_lines: lines.get(&candidate.id).cloned().unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::{LINE_PLAN_MAX_MATCHED_LINES, auto_plan, candidate_page_size};
    use crate::model::SearchPlan;

    #[test]
    fn the_plan_switches_at_the_named_threshold() {
        assert_eq!(auto_plan(0), SearchPlan::LineDriven);
        assert_eq!(
            auto_plan(LINE_PLAN_MAX_MATCHED_LINES - 1),
            SearchPlan::LineDriven
        );
        assert_eq!(
            auto_plan(LINE_PLAN_MAX_MATCHED_LINES),
            SearchPlan::FrameScan
        );
    }

    #[test]
    fn a_candidate_page_grows_with_the_limit_and_stays_bounded() {
        assert_eq!(candidate_page_size(1), 25);
        assert_eq!(candidate_page_size(2), 50);
        assert_eq!(candidate_page_size(20), 500);
        assert_eq!(candidate_page_size(1_000), 500);
    }
}
