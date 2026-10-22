//! Search: accents, prefixes, filters, moments, limits, and FTS errors.

mod common;

use common::{
    APP, APP_NAME, TITLE, TestResult, begin_segment, frame, line, open_store, search_params,
    simple_frame,
};
use erst_store::{SearchParams, SearchPlan, StoreError};

#[test]
fn accents_match_in_both_directions() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["canción de prueba"]))?;
    store.insert_frame(&frame(
        segment_id,
        1_200_000,
        APP,
        APP_NAME,
        Some("Other Window"),
        vec![line("cancion sin acento", 0)],
    ))?;

    assert_eq!(store.search(&search_params("cancion", 10))?.len(), 2);
    assert_eq!(store.search(&search_params("canción", 10))?.len(), 2);
    assert_eq!(store.search(&search_params("\"canción\"", 10))?.len(), 2);
    Ok(())
}

#[test]
fn prefix_expression_matches_longer_words() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["pinnacle systems"]))?;

    let hits = store.search(&search_params("\"pinn\"*", 10))?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].matched_lines[0].text, "pinnacle systems");
    Ok(())
}

#[test]
fn app_filter_matches_name_and_bundle_id_case_insensitively() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&frame(
        segment_id,
        1_000,
        "com.apple.Safari",
        "Safari",
        Some(TITLE),
        vec![line("shared needle", 0)],
    ))?;
    store.insert_frame(&frame(
        segment_id,
        1_200_000,
        "com.microsoft.VSCode",
        "Visual Studio Code",
        Some(TITLE),
        vec![line("shared needle", 0)],
    ))?;

    let by_name = store.search(&SearchParams {
        app: Some("Safari".to_owned()),
        ..search_params("needle", 10)
    })?;
    assert_eq!(by_name.len(), 1);
    assert_eq!(by_name[0].app_name, "Safari");

    let lower_name = store.search(&SearchParams {
        app: Some("safari".to_owned()),
        ..search_params("needle", 10)
    })?;
    assert_eq!(lower_name.len(), 1);

    let by_bundle = store.search(&SearchParams {
        app: Some("COM.MICROSOFT.VSCODE".to_owned()),
        ..search_params("needle", 10)
    })?;
    assert_eq!(by_bundle.len(), 1);
    assert_eq!(by_bundle[0].app_name, "Visual Studio Code");

    let by_full_name = store.search(&SearchParams {
        app: Some("Visual Studio Code".to_owned()),
        ..search_params("needle", 10)
    })?;
    assert_eq!(by_full_name.len(), 1);

    let partial = store.search(&SearchParams {
        app: Some("Visual".to_owned()),
        ..search_params("needle", 10)
    })?;
    assert_eq!(partial.len(), 0);
    Ok(())
}

#[test]
fn time_filters_include_since_and_exclude_until() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let first = store.insert_frame(&simple_frame(segment_id, 1_000, &["time needle"]))?;
    let second = store.insert_frame(&simple_frame(segment_id, 2_000, &["time needle"]))?;
    let third = store.insert_frame(&simple_frame(segment_id, 3_000, &["time needle"]))?;

    let hits = store.search(&SearchParams {
        since_ms: Some(2_000),
        until_ms: Some(2_500),
        ..search_params("needle", 10)
    })?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, second);

    let between = store.search(&SearchParams {
        since_ms: Some(2_001),
        until_ms: Some(3_001),
        ..search_params("needle", 10)
    })?;
    assert_eq!(between.len(), 1);
    assert_eq!(between[0].frame_id, third);

    // `since` is inclusive and `until` is exclusive, so the frame at the
    // upper boundary belongs to the next range only.
    let boundary_query = SearchParams {
        since_ms: Some(0),
        until_ms: Some(2_000),
        ..search_params("needle", 10)
    };
    for plan in [SearchPlan::LineDriven, SearchPlan::FrameScan] {
        let boundary = store.search_with_plan(&boundary_query, plan)?;
        assert_eq!(boundary.len(), 1, "{plan:?}");
        assert_eq!(boundary[0].frame_id, first, "{plan:?}");
    }

    let at_start = store.search(&SearchParams {
        since_ms: Some(1_000),
        until_ms: Some(1_001),
        ..search_params("needle", 10)
    })?;
    assert_eq!(at_start.len(), 1);
    assert_eq!(at_start[0].frame_id, first);

    let empty = store.search(&SearchParams {
        since_ms: Some(0),
        until_ms: Some(999),
        ..search_params("needle", 10)
    })?;
    assert_eq!(empty.len(), 0);
    Ok(())
}

#[test]
fn groups_frames_into_moments_across_gaps_and_windows() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    // Group 1: same app and window, 60 seconds apart.
    let first = store.insert_frame(&frame(
        segment_id,
        0,
        APP,
        APP_NAME,
        Some("A"),
        vec![line("moment needle", 0)],
    ))?;
    let second = store.insert_frame(&frame(
        segment_id,
        60_000,
        APP,
        APP_NAME,
        Some("A"),
        vec![line("moment needle", 0), line("second needle", 1)],
    ))?;
    // Exactly ten minutes after the previous frame: a new moment.
    let third = store.insert_frame(&frame(
        segment_id,
        660_000,
        APP,
        APP_NAME,
        Some("A"),
        vec![line("moment needle", 0)],
    ))?;
    // Window change splits the moment immediately.
    let fourth = store.insert_frame(&frame(
        segment_id,
        661_000,
        APP,
        APP_NAME,
        Some("B"),
        vec![line("moment needle", 0)],
    ))?;
    // App change splits it too.
    let fifth = store.insert_frame(&frame(
        segment_id,
        662_000,
        "com.example.Other",
        "Other",
        Some("A"),
        vec![line("moment needle", 0)],
    ))?;
    // More than ten minutes after the previous frame: a new moment again.
    let sixth = store.insert_frame(&frame(
        segment_id,
        1_262_001,
        "com.example.Other",
        "Other",
        Some("A"),
        vec![line("moment needle", 0)],
    ))?;

    let hits = store.search(&search_params("needle", 10))?;
    assert_eq!(hits.len(), 5);
    assert_eq!(hits[0].frame_id, sixth);
    assert_eq!(hits[1].frame_id, fifth);
    assert_eq!(hits[2].frame_id, fourth);
    assert_eq!(hits[3].frame_id, third);
    assert_eq!(hits[4].frame_id, second);
    assert_eq!(hits[4].first_seen_ms, 0);
    assert_eq!(hits[4].last_seen_ms, 60_000);
    assert_eq!(hits[4].matched_lines.len(), 2);
    assert_ne!(hits[4].frame_id, first);

    let limited = store.search(&search_params("needle", 2))?;
    assert_eq!(limited.len(), 2);
    assert_eq!(limited[0].frame_id, sixth);
    assert_eq!(limited[1].frame_id, fifth);
    Ok(())
}

#[test]
fn one_long_session_does_not_hide_older_moments() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let base = 1_800_000_000_000_i64;
    let older = store.insert_frame(&frame(
        segment_id,
        base,
        "com.example.Other",
        "Other",
        Some("Notes"),
        vec![line("alpha old", 0)],
    ))?;
    let session_start = base + 2 * 3_600_000;
    let mut last_session_id = older;
    for index in 0..300_i64 {
        last_session_id = store.insert_frame(&frame(
            segment_id,
            session_start + index * 2_000,
            APP,
            APP_NAME,
            Some("Window"),
            vec![line("alpha session", 0)],
        ))?;
    }

    for plan in [SearchPlan::LineDriven, SearchPlan::FrameScan] {
        let hits = store.search_with_plan(&search_params("\"alpha\"*", 2), plan)?;
        assert_eq!(hits.len(), 2, "{plan:?}");
        assert_eq!(hits[0].frame_id, last_session_id);
        assert_eq!(hits[0].first_seen_ms, session_start);
        assert_eq!(hits[0].last_seen_ms, session_start + 299 * 2_000);
        assert_eq!(hits[1].frame_id, older);
        assert_eq!(hits[1].app_name, "Other");
    }

    let auto = store.search(&search_params("\"alpha\"*", 2))?;
    assert_eq!(auto.len(), 2);
    Ok(())
}

#[test]
fn representative_ties_go_to_the_most_recent_frame() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let earlier = store.insert_frame(&simple_frame(segment_id, 1_000, &["tie needle"]))?;
    let later = store.insert_frame(&simple_frame(segment_id, 2_000, &["tie needle"]))?;
    let hits = store.search(&search_params("needle", 10))?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, later);
    assert_ne!(hits[0].frame_id, earlier);
    Ok(())
}

#[test]
fn search_hit_carries_frame_metadata() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let mut new_frame = frame(
        segment_id,
        5_000,
        APP,
        APP_NAME,
        Some("Docs"),
        vec![line("metadata needle", 0)],
    );
    new_frame.url = Some("https://example.com/page".to_owned());
    new_frame.pts_ms = 4_321;
    let frame_id = store.insert_frame(&new_frame)?;

    let hits = store.search(&search_params("needle", 10))?;
    assert_eq!(hits.len(), 1);
    let hit = &hits[0];
    assert_eq!(hit.frame_id, frame_id);
    assert_eq!(hit.captured_at, 5_000);
    assert_eq!(hit.bundle_id, APP);
    assert_eq!(hit.app_name, APP_NAME);
    assert_eq!(hit.window_title.as_deref(), Some("Docs"));
    assert_eq!(hit.url.as_deref(), Some("https://example.com/page"));
    assert_eq!(
        hit.segment_path.as_deref(),
        Some("segments/2026/10/20/120000-1.mp4")
    );
    assert_eq!(hit.pts_ms, 4_321);
    assert_eq!(hit.matched_lines.len(), 1);
    assert_eq!(hit.matched_lines[0].text, "metadata needle");
    Ok(())
}

#[test]
fn empty_match_and_zero_limit_return_no_hits() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["needle"]))?;

    assert_eq!(store.search(&search_params("   ", 10))?.len(), 0);
    assert_eq!(store.search(&search_params("", 10))?.len(), 0);
    assert_eq!(store.search(&search_params("needle", 0))?.len(), 0);
    Ok(())
}

#[test]
fn invalid_fts_syntax_is_an_error() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["needle"]))?;

    let result = store.search(&search_params("\"unclosed", 10));
    assert!(matches!(result, Err(StoreError::Sqlite(_))));
    Ok(())
}

#[test]
fn both_search_plans_return_the_same_moments() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    for index in 0..40 {
        let captured_at = 1_000 + i64::from(index) * 2_000;
        let bundle_id = if index % 2 == 0 {
            "com.apple.Safari"
        } else {
            "com.microsoft.VSCode"
        };
        let app_name = if index % 2 == 0 {
            "Safari"
        } else {
            "Visual Studio Code"
        };
        let mut lines = vec![line("common terminal output", 0)];
        if index % 7 == 0 {
            lines.push(line("rare needle", 1));
        }
        store.insert_frame(&frame(
            segment_id,
            captured_at,
            bundle_id,
            app_name,
            Some("Window"),
            lines,
        ))?;
    }

    let queries = [
        search_params("needle", 5),
        search_params("common", 5),
        SearchParams {
            app: Some("Safari".to_owned()),
            ..search_params("needle", 5)
        },
        SearchParams {
            since_ms: Some(20_000),
            until_ms: Some(50_000),
            ..search_params("needle", 5)
        },
    ];
    for query in &queries {
        let auto = store.search(query)?;
        let line_driven = store.search_with_plan(query, SearchPlan::LineDriven)?;
        let frame_scan = store.search_with_plan(query, SearchPlan::FrameScan)?;
        assert_eq!(auto, line_driven, "{query:?}");
        assert_eq!(auto, frame_scan, "{query:?}");
        assert!(!auto.is_empty(), "{query:?}");
    }
    Ok(())
}
