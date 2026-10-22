//! Reads: ranges, detail, navigation, spans, and segments.

mod common;

use common::{APP, APP_NAME, TestResult, begin_segment, frame, line, open_store, simple_frame};
use erst_store::StoreError;

#[test]
fn frames_in_range_is_ascending_and_half_open() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let first = store.insert_frame(&simple_frame(segment_id, 1_000, &["a"]))?;
    let second = store.insert_frame(&simple_frame(segment_id, 2_000, &["b"]))?;
    let third = store.insert_frame(&simple_frame(segment_id, 3_000, &["c"]))?;
    store.insert_frame(&simple_frame(segment_id, 4_000, &["d"]))?;

    let middle = store.frames_in_range(1_500, 3_500)?;
    assert_eq!(
        middle.iter().map(|stamp| stamp.id).collect::<Vec<_>>(),
        vec![second, third]
    );
    let edge = store.frames_in_range(2_000, 3_000)?;
    assert_eq!(
        edge.iter().map(|stamp| stamp.id).collect::<Vec<_>>(),
        vec![second]
    );
    assert_eq!(store.frames_in_range(3_000, 2_000)?.len(), 0);
    assert_eq!(store.frames_in_range(0, 10_000)?.len(), 4);
    assert_eq!(
        store.frames_in_range(0, 10_000)?.first().map(|s| s.id),
        Some(first)
    );
    Ok(())
}

#[test]
fn frame_detail_returns_app_segment_and_ordered_lines() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let mut new_frame = frame(
        segment_id,
        5_000,
        APP,
        APP_NAME,
        Some("Detail Window"),
        vec![line("top line", 0), line("bottom line", 1)],
    );
    new_frame.url = Some("https://example.com/detail".to_owned());
    new_frame.pts_ms = 1_234;
    let frame_id = store.insert_frame(&new_frame)?;

    let detail = store.frame_detail(frame_id)?;
    assert_eq!(detail.stamp.id, frame_id);
    assert_eq!(detail.stamp.captured_at, 5_000);
    assert!((detail.stamp.change_ratio - 0.01).abs() < f32::EPSILON);
    assert_eq!(detail.bundle_id, APP);
    assert_eq!(detail.app_name, APP_NAME);
    assert_eq!(detail.window_title.as_deref(), Some("Detail Window"));
    assert_eq!(detail.url.as_deref(), Some("https://example.com/detail"));
    assert_eq!(detail.segment_id, segment_id);
    assert_eq!(
        detail.segment_path.as_deref(),
        Some("segments/2026/10/20/120000-1.mp4")
    );
    assert_eq!(detail.segment_started_at, 0);
    assert_eq!(detail.pts_ms, 1_234);
    assert_eq!(detail.tier, 0);
    assert_eq!(detail.lines.len(), 2);
    assert_eq!(detail.lines[0].text, "top line");
    assert_eq!(detail.lines[0].x, 100);
    assert_eq!(detail.lines[0].y, 100);
    assert_eq!(detail.lines[0].w, 1_000);
    assert_eq!(detail.lines[0].h, 100);
    assert_eq!(detail.lines[1].text, "bottom line");
    assert!(matches!(
        store.frame_detail(9_999),
        Err(StoreError::NotFound { what: "frame", .. })
    ));
    Ok(())
}

#[test]
fn nearest_frame_prefers_the_closest_and_then_the_earlier() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let first = store.insert_frame(&simple_frame(segment_id, 1_000, &["a"]))?;
    let second = store.insert_frame(&simple_frame(segment_id, 3_000, &["b"]))?;
    let third = store.insert_frame(&simple_frame(segment_id, 5_000, &["c"]))?;

    assert_eq!(store.nearest_frame(100)?.map(|stamp| stamp.id), Some(first));
    assert_eq!(
        store.nearest_frame(2_800)?.map(|stamp| stamp.id),
        Some(second)
    );
    assert_eq!(
        store.nearest_frame(3_999)?.map(|stamp| stamp.id),
        Some(second)
    );
    assert_eq!(
        store.nearest_frame(4_000)?.map(|stamp| stamp.id),
        Some(second)
    );
    assert_eq!(
        store.nearest_frame(9_000)?.map(|stamp| stamp.id),
        Some(third)
    );

    let empty_dir = tempfile::tempdir()?;
    let empty = erst_store::Store::open(&empty_dir.path().join("empty.sqlite"))?;
    assert!(empty.nearest_frame(1_000)?.is_none());
    Ok(())
}

#[test]
fn neighbors_return_before_and_after_in_time_order() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let first = store.insert_frame(&simple_frame(segment_id, 1_000, &["a"]))?;
    let second = store.insert_frame(&simple_frame(segment_id, 2_000, &["b"]))?;
    let third = store.insert_frame(&simple_frame(segment_id, 3_000, &["c"]))?;
    let fourth = store.insert_frame(&simple_frame(segment_id, 4_000, &["d"]))?;

    let around = store.neighbors(second, 1, 1)?;
    assert_eq!(
        around.iter().map(|stamp| stamp.id).collect::<Vec<_>>(),
        vec![first, third]
    );
    let earlier = store.neighbors(second, 10, 0)?;
    assert_eq!(
        earlier.iter().map(|stamp| stamp.id).collect::<Vec<_>>(),
        vec![first]
    );
    let later = store.neighbors(first, 0, 10)?;
    assert_eq!(
        later.iter().map(|stamp| stamp.id).collect::<Vec<_>>(),
        vec![second, third, fourth]
    );
    assert!(matches!(
        store.neighbors(9_999, 1, 1),
        Err(StoreError::NotFound { what: "frame", .. })
    ));
    Ok(())
}

#[test]
fn spans_overlapping_a_range_include_open_spans() -> TestResult {
    let (_dir, store) = open_store()?;
    let open = store.begin_span(APP, APP_NAME, Some("Open Window"), None, 100)?;
    let closed = store.begin_span(APP, APP_NAME, Some("Closed Window"), None, 200)?;
    store.end_span(closed, 300)?;
    let edge = store.begin_span(APP, "Other", Some("Edge"), None, 400)?;
    store.end_span(edge, 500)?;

    let spans = store.spans_in_range(250, 450)?;
    assert_eq!(spans.len(), 3);
    assert_eq!(spans[0].id, open);
    assert_eq!(spans[0].window_title.as_deref(), Some("Open Window"));
    assert_eq!(spans[0].ended_at, None);
    assert_eq!(spans[1].id, closed);
    assert_eq!(spans[1].ended_at, Some(300));
    assert_eq!(spans[2].id, edge);
    assert_eq!(spans[2].app_name, "Other");

    let touching = store.spans_in_range(300, 400)?;
    assert_eq!(touching.len(), 1);
    assert_eq!(touching[0].id, open);
    // An open span keeps overlapping every later range until it ends.
    let later = store.spans_in_range(600, 700)?;
    assert_eq!(
        later.iter().map(|span| span.id).collect::<Vec<_>>(),
        vec![open]
    );
    assert_eq!(store.spans_in_range(0, 100)?.len(), 0);
    Ok(())
}

#[test]
fn spans_in_range_include_only_overlapping_closed_spans() -> TestResult {
    let (_dir, store) = open_store()?;
    let covering = store.begin_span(APP, APP_NAME, Some("Covering"), None, 50)?;
    store.end_span(covering, 350)?;
    let before = store.begin_span(APP, APP_NAME, Some("Before"), None, 50)?;
    store.end_span(before, 150)?;
    let ending_at_start = store.begin_span(APP, APP_NAME, Some("Ending at start"), None, 150)?;
    store.end_span(ending_at_start, 200)?;
    let starting_at_end = store.begin_span(APP, APP_NAME, Some("Starting at end"), None, 250)?;
    store.end_span(starting_at_end, 300)?;
    let open_before = store.begin_span(APP, APP_NAME, Some("Open before"), None, 100)?;
    let open_after = store.begin_span(APP, APP_NAME, Some("Open after"), None, 300)?;

    let spans = store.spans_in_range(200, 250)?;
    assert_eq!(
        spans.iter().map(|span| span.id).collect::<Vec<_>>(),
        vec![covering, open_before]
    );
    assert_eq!(spans[0].window_title.as_deref(), Some("Covering"));
    assert_eq!(spans[1].ended_at, None);
    assert_eq!(store.spans_in_range(0, 50)?.len(), 0);
    assert!(
        !store
            .spans_in_range(200, 250)?
            .iter()
            .any(|span| span.id == open_after)
    );
    Ok(())
}

#[test]
fn segments_list_newest_first_and_open_segment_is_the_unfinished_one() -> TestResult {
    let (_dir, store) = open_store()?;
    let first = store.begin_segment("segments/a.mp4", 100, 1920, 1080)?;
    store.finish_segment(first, 200, 1_000)?;
    let second = store.begin_segment("segments/b.mp4", 300, 1280, 720)?;

    let segments = store.segments()?;
    assert_eq!(segments.len(), 2);
    assert_eq!(segments[0].id, second);
    assert_eq!(segments[0].path.as_deref(), Some("segments/b.mp4"));
    assert_eq!(segments[0].started_at, 300);
    assert_eq!(segments[0].ended_at, None);
    assert_eq!(segments[0].width, 1280);
    assert_eq!(segments[0].height, 720);
    assert_eq!(segments[0].bytes, 0);
    assert_eq!(segments[0].tier, 0);
    assert_eq!(segments[1].id, first);
    assert_eq!(segments[1].ended_at, Some(200));
    assert_eq!(segments[1].bytes, 1_000);

    assert_eq!(
        store.open_segment()?.map(|segment| segment.id),
        Some(second)
    );
    store.finish_segment(second, 400, 2_000)?;
    assert!(store.open_segment()?.is_none());
    Ok(())
}

#[test]
fn last_span_before_returns_the_latest_closed_visit_of_one_window() -> TestResult {
    let (_dir, store) = open_store()?;
    let early = store.begin_span(APP, APP_NAME, Some("Docs"), None, 100)?;
    store.end_span(early, 200)?;
    let late = store.begin_span(APP, APP_NAME, Some("Docs"), None, 300)?;
    store.end_span(late, 400)?;
    let other_window = store.begin_span(APP, APP_NAME, Some("Other"), None, 500)?;
    store.end_span(other_window, 600)?;
    let other_app = store.begin_span("com.example.Other", "Other", Some("Docs"), None, 700)?;
    store.end_span(other_app, 800)?;
    // An open visit ending after the boundary must not be reported.
    let open = store.begin_span(APP, APP_NAME, Some("Docs"), None, 900)?;
    store.end_span(open, 1_100)?;

    assert_eq!(
        store
            .last_span_before(APP, Some("Docs"), 1_000)?
            .map(|span| span.id),
        Some(late)
    );
    assert_eq!(
        store
            .last_span_before(APP, Some("Docs"), 1_000)?
            .map(|span| span.ended_at),
        Some(Some(400))
    );
    // Exactly on the boundary counts as before it.
    assert_eq!(
        store
            .last_span_before(APP, Some("Docs"), 400)?
            .map(|span| span.id),
        Some(late)
    );
    assert_eq!(
        store
            .last_span_before(APP, Some("Docs"), 200)?
            .map(|span| span.id),
        Some(early)
    );
    assert!(store.last_span_before(APP, Some("Docs"), 199)?.is_none());
    assert_eq!(
        store
            .last_span_before(APP, Some("Other"), 1_000)?
            .map(|span| span.id),
        Some(other_window)
    );
    assert_eq!(
        store
            .last_span_before("com.example.Other", Some("Docs"), 1_000)?
            .map(|span| span.id),
        Some(other_app)
    );
    assert!(
        store
            .last_span_before(APP, Some("Missing"), 1_000)?
            .is_none()
    );
    assert!(store.last_span_before(APP, Some("Docs"), 100)?.is_none());
    Ok(())
}
