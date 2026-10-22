//! Seeded benchmark for the two hot store paths.
//!
//! Insert: 2,000 frames with 80 lines each where 90% of the lines repeat
//! between consecutive frames, timed against the `record_frame` budget.
//!
//! Search: 300,000 frames and 1,000,000 frame lines over 90 days, with text
//! drawn from a Zipf-like vocabulary and a few rare words near the oldest
//! frames. The lines are written in the version 4 layout and then packed by the
//! real migration, which is timed too. Every query runs under both access plans
//! and reports median and p95 against the `search` budget in `docs/HYGIENE.md`.
//!
//! Run with `cargo run --release -p erst-store --example bench_store`.

#![allow(
    clippy::print_stdout,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss
)]

use std::error::Error;
use std::path::Path;
use std::time::{Duration, Instant};

use erst_store::{LineSource, NewFrame, NewLine, SearchParams, SearchPlan, Store};
use rusqlite::{Connection, OpenFlags};

const INSERT_FRAMES: usize = 2_000;
const INSERT_LINES_PER_FRAME: usize = 80;
const INSERT_PERSISTENT_LINES: usize = 72;
const INSERT_BUDGET_MS: f64 = 2.0;

const SEARCH_FRAMES: usize = 300_000;
const SEARCH_FRAME_LINES: usize = 1_000_000;
/// Frames with four lines instead of three, which makes the total exactly one
/// million frame lines.
const DENSE_FRAMES: usize = 100_000;
const DENSE_LINES_PER_FRAME: usize = 4;
const SPARSE_LINES_PER_FRAME: usize = 3;
const SEARCH_DAYS: usize = 90;
const SEARCH_LIMIT: u32 = 20;
const SEARCH_RUNS: usize = 9;
const SEARCH_BUDGET_MS: f64 = 50.0;
const VOCABULARY_SIZE: usize = 2_000;
const APP_COUNT: usize = 6;
/// The vocabulary word with the highest probability, used as the common query.
const COMMON_WORD: &str = "w0000";
/// A mid-frequency word with about 20,000 matches, used to show both plans
/// around the switch threshold.
const THRESHOLD_WORD: &str = "w0001";
/// A token stored only in the oldest frames, used as the rare query.
const RARE_WORD: &str = "zebracrypt";
const DAY_MS: i64 = 86_400_000;
const BASE_MS: i64 = 1_700_000_000_000;

fn main() -> Result<(), Box<dyn Error>> {
    let mut failed = false;
    let insert_ms = bench_insert()?;
    println!(
        "insert_frame: {insert_ms:.3} ms mean over {INSERT_FRAMES} frames with {INSERT_LINES_PER_FRAME} lines"
    );
    if insert_ms >= INSERT_BUDGET_MS {
        println!("FAIL insert_frame mean {insert_ms:.3} ms is over {INSERT_BUDGET_MS:.1} ms");
        failed = true;
    }

    let search_failed = bench_search()?;
    failed |= search_failed;

    if failed {
        return Err(std::io::Error::other("benchmark budget exceeded").into());
    }
    println!("PASS both budgets");
    Ok(())
}

/// Times `insert_frame` on a small database and returns the mean milliseconds.
fn bench_insert() -> Result<f64, Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let store = Store::open(&dir.path().join("insert.sqlite"))?;
    let segment_id = store.begin_segment("segments/bench.mp4", 0, 1920, 1080)?;
    let persistent: Vec<NewLine> = (0..INSERT_PERSISTENT_LINES)
        .map(|index| NewLine {
            text: format!("persistent alpha beta line {index}"),
            x: 100,
            y: u16::try_from(index * 100).unwrap_or(u16::MAX),
            w: 900,
            h: 80,
            source: LineSource::Ocr,
        })
        .collect();

    let mut insert_time = Duration::ZERO;
    for index in 0..INSERT_FRAMES {
        let mut lines = persistent.clone();
        for slot in INSERT_PERSISTENT_LINES..INSERT_LINES_PER_FRAME {
            let token = index * (INSERT_LINES_PER_FRAME - INSERT_PERSISTENT_LINES)
                + (slot - INSERT_PERSISTENT_LINES);
            lines.push(NewLine {
                text: format!("fresh frame {index} slot {slot} token{token}"),
                x: 100,
                y: u16::try_from(slot * 100).unwrap_or(u16::MAX),
                w: 900,
                h: 80,
                source: LineSource::Ocr,
            });
        }
        let captured_at = i64::try_from(index).unwrap_or(i64::MAX) * 2_000;
        let frame = NewFrame {
            captured_at,
            segment_id,
            pts_ms: captured_at,
            bundle_id: "com.example.Bench".to_owned(),
            app_name: "Bench".to_owned(),
            window_title: Some("Window".to_owned()),
            url: None,
            change_ratio: 0.01,
            lines,
        };
        let started = Instant::now();
        store.insert_frame(&frame)?;
        insert_time += started.elapsed();
    }
    let frames = f64::from(u32::try_from(INSERT_FRAMES).unwrap_or(u32::MAX));
    Ok(insert_time.as_secs_f64() * 1_000.0 / frames)
}

/// One measured query shape.
struct BenchQuery {
    name: &'static str,
    params: SearchParams,
}

/// Builds the large database, times every query under both plans, and returns
/// whether any query broke the budget under the automatic plan.
fn bench_search() -> Result<bool, Box<dyn Error>> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("search.sqlite");
    let (line_count, frame_count) = build_search_database(&path)?;
    let started = Instant::now();
    let store = Store::open(&path)?;
    println!(
        "migration to packed layouts: {:.2} s for {line_count} frame lines",
        started.elapsed().as_secs_f64()
    );
    Connection::open(&path)?.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
    assert_eq!(line_count, SEARCH_FRAME_LINES);
    assert_eq!(frame_count, SEARCH_FRAMES);
    let size_mb = std::fs::metadata(&path)?.len() as f64 / 1_000_000.0;
    println!(
        "search database: {frame_count} frames, {line_count} frame lines, {size_mb:.1} MB after WAL checkpoint"
    );

    let day = BASE_MS + 40 * DAY_MS;
    let queries = [
        BenchQuery {
            name: "rare word",
            params: search_params(format!("\"{RARE_WORD}\"")),
        },
        BenchQuery {
            name: "common word",
            params: search_params(COMMON_WORD.to_owned()),
        },
        BenchQuery {
            name: "threshold word",
            params: search_params(THRESHOLD_WORD.to_owned()),
        },
        BenchQuery {
            name: "app filtered",
            params: SearchParams {
                app: Some("App0".to_owned()),
                ..search_params(format!("\"{RARE_WORD}\""))
            },
        },
        BenchQuery {
            name: "date filtered",
            params: SearchParams {
                since_ms: Some(day),
                until_ms: Some(day + DAY_MS),
                ..search_params(COMMON_WORD.to_owned())
            },
        },
    ];

    let counter = Connection::open_with_flags(&path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let mut failed = false;
    for query in &queries {
        let matched: i64 = counter.query_row(
            "SELECT COUNT(*) FROM text_lines_fts WHERE text_lines_fts MATCH ?1",
            [&query.params.fts_match],
            |row| row.get(0),
        )?;
        println!(
            "query: {} ({} matched lines)",
            query.name,
            u64::try_from(matched).unwrap_or(u64::MAX)
        );
        for plan in [SearchPlan::FrameScan, SearchPlan::LineDriven] {
            let (median, p95, hits) = measure(&store, &query.params, plan)?;
            println!(
                "  {:<12} median {median:8.3} ms  p95 {p95:8.3} ms  ({hits} hits)",
                plan_name(plan)
            );
        }
        let (median, p95, hits) = measure_auto(&store, &query.params)?;
        println!(
            "  {:<12} median {median:8.3} ms  p95 {p95:8.3} ms  ({hits} hits)",
            "auto"
        );
        if p95 >= SEARCH_BUDGET_MS {
            println!(
                "FAIL search p95 {p95:.3} ms is over {SEARCH_BUDGET_MS:.1} ms for {}",
                query.name
            );
            failed = true;
        }
    }
    Ok(failed)
}

fn search_params(fts_match: String) -> SearchParams {
    SearchParams {
        fts_match,
        app: None,
        since_ms: None,
        until_ms: None,
        limit: SEARCH_LIMIT,
    }
}

fn plan_name(plan: SearchPlan) -> &'static str {
    match plan {
        SearchPlan::Auto => "auto",
        SearchPlan::FrameScan => "frame scan",
        SearchPlan::LineDriven => "line driven",
    }
}

fn measure(
    store: &Store,
    params: &SearchParams,
    plan: SearchPlan,
) -> Result<(f64, f64, usize), Box<dyn Error>> {
    let expected = store.search_with_plan(params, plan)?.len();
    let mut samples = Vec::with_capacity(SEARCH_RUNS);
    for _ in 0..SEARCH_RUNS {
        let started = Instant::now();
        let hits = store.search_with_plan(params, plan)?;
        samples.push(started.elapsed().as_secs_f64() * 1_000.0);
        assert_eq!(hits.len(), expected);
    }
    Ok((
        percentile(&mut samples, 50),
        percentile(&mut samples, 95),
        expected,
    ))
}

fn measure_auto(store: &Store, params: &SearchParams) -> Result<(f64, f64, usize), Box<dyn Error>> {
    let expected = store.search(params)?.len();
    let mut samples = Vec::with_capacity(SEARCH_RUNS);
    for _ in 0..SEARCH_RUNS {
        let started = Instant::now();
        let hits = store.search(params)?;
        samples.push(started.elapsed().as_secs_f64() * 1_000.0);
        assert_eq!(hits.len(), expected);
    }
    Ok((
        percentile(&mut samples, 50),
        percentile(&mut samples, 95),
        expected,
    ))
}

/// Nearest-rank percentile of a sample set.
fn percentile(samples: &mut [f64], percentile: usize) -> f64 {
    samples.sort_by(f64::total_cmp);
    if samples.is_empty() {
        return 0.0;
    }
    let rank = (samples.len() * percentile).div_ceil(100);
    samples[rank.saturating_sub(1).min(samples.len() - 1)]
}

/// The migrations of a version 4 database, which still stores one row per line.
const VERSION_FOUR: [&str; 4] = [
    include_str!("../migrations/0001_init.sql"),
    include_str!("../migrations/0002_secure_delete.sql"),
    include_str!("../migrations/0003_pending_unlinks.sql"),
    include_str!("../migrations/0004_line_sources.sql"),
];

/// Fills a version 4 database in one transaction through a direct connection,
/// which is far faster than 300,000 `insert_frame` calls and still exercises
/// the real triggers. Opening the store afterwards packs it with the real
/// migration.
fn build_search_database(path: &Path) -> Result<(usize, usize), Box<dyn Error>> {
    let mut connection = Connection::open(path)?;
    connection.pragma_update(None, "auto_vacuum", "INCREMENTAL")?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    for migration in VERSION_FOUR {
        connection.execute_batch(migration)?;
    }
    connection.pragma_update(None, "user_version", 4)?;
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.pragma_update(None, "synchronous", "OFF")?;
    let transaction = connection.transaction()?;
    for day in 0..SEARCH_DAYS {
        let day = i64::try_from(day).unwrap_or(i64::MAX);
        transaction.execute(
            "INSERT INTO segments (path, started_at, ended_at, width, height, bytes)
             VALUES (?1, ?2, ?3, 1920, 1080, 1000)",
            rusqlite::params![
                format!("segments/bench-{day:03}.mp4"),
                BASE_MS + day * DAY_MS,
                BASE_MS + (day + 1) * DAY_MS
            ],
        )?;
    }
    for app in 0..APP_COUNT {
        transaction.execute(
            "INSERT INTO apps (bundle_id, name) VALUES (?1, ?2)",
            [format!("com.example.App{app}"), format!("App{app}")],
        )?;
    }

    let mut words = Words::new();
    let mut frame_line_count = 0_usize;
    {
        let mut insert_frame = transaction.prepare_cached(
            "INSERT INTO frames (captured_at, segment_id, pts_ms, app_id, window_title, url, change_ratio)
             VALUES (?1, ?2, ?3, ?4, ?5, NULL, ?6)",
        )?;
        let mut insert_line =
            transaction.prepare_cached("INSERT INTO text_lines (hash, text) VALUES (?1, ?2)")?;
        let mut insert_frame_line = transaction.prepare_cached(
            "INSERT INTO frame_lines (frame_id, line_id, x, y, w, h) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        )?;

        for index in 0..SEARCH_FRAMES {
            let day = index * SEARCH_DAYS / SEARCH_FRAMES;
            let captured_at = BASE_MS
                + i64::try_from(day).unwrap_or(i64::MAX) * DAY_MS
                + i64::try_from(index).unwrap_or(i64::MAX);
            let app = index % APP_COUNT;
            insert_frame.execute(rusqlite::params![
                captured_at,
                i64::try_from(day).unwrap_or(i64::MAX) + 1,
                captured_at,
                i64::try_from(app).unwrap_or(i64::MAX) + 1,
                "Window",
                0.01_f64,
            ])?;
            let frame_id = transaction.last_insert_rowid();
            let lines = if index < DENSE_FRAMES {
                DENSE_LINES_PER_FRAME
            } else {
                SPARSE_LINES_PER_FRAME
            };
            for slot in 0..lines {
                let (hash, text) = words.line(index, slot);
                insert_line.execute(rusqlite::params![hash.as_slice(), text])?;
                let line_id = transaction.last_insert_rowid();
                insert_frame_line.execute(rusqlite::params![
                    frame_id,
                    line_id,
                    i64::try_from(slot).unwrap_or(i64::MAX),
                    0_i64,
                    1_000_i64,
                    100_i64,
                ])?;
                frame_line_count += 1;
            }
        }
    }
    transaction.commit()?;
    connection.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
    drop(connection);
    Ok((frame_line_count, SEARCH_FRAMES))
}

/// Deterministic Zipf-like text generator. `rank = V * u^3` makes small ranks
/// (common words) frequent and large ranks rare, and every line carries a
/// unique document and paragraph token so no two lines collapse into one.
struct Words {
    state: u64,
}

impl Words {
    fn new() -> Self {
        Self {
            state: 0x9e37_79b9_7f4a_7c15,
        }
    }

    fn next_unit(&mut self) -> f64 {
        self.state = self
            .state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        // 53 random bits scaled into [0, 1).
        f64::from_bits(0x3ff0_0000_0000_0000 | (self.state >> 11)) - 1.0
    }

    /// A 16-byte unique hash and the line text for one slot of one frame.
    fn line(&mut self, frame: usize, slot: usize) -> ([u8; 16], String) {
        let rank = (self.next_unit().powi(3) * VOCABULARY_SIZE as f64) as usize;
        let paragraph = (self.next_unit() * 1_000_000.0) as usize;
        let mut text = format!("w{rank:04} doc{frame:06} para{paragraph:06} slot{slot}");
        // Rare tokens live in the oldest frames, which is the worst case for a
        // newest-first frame scan.
        if frame < 4 && slot == 0 {
            text.push(' ');
            text.push_str(RARE_WORD);
        }
        let hash = ((frame as u128) << 8 | slot as u128).to_le_bytes();
        (hash, text)
    }
}
