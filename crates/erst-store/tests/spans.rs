//! Span bookkeeping when a previous process left rows open.

mod common;

use common::{TestResult, begin_segment, open_store, simple_frame};

#[test]
fn close_open_spans_ends_at_the_newest_frame_or_its_own_start() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    store.insert_frame(&simple_frame(segment_id, 1_000, &["only frame"]))?;
    let before = store.begin_span("com.example.Before", "Before", None, None, 400)?;
    let after = store.begin_span("com.example.After", "After", None, None, 5_000)?;
    let closed = store.begin_span("com.example.Closed", "Closed", None, None, 100)?;
    store.end_span(closed, 200)?;

    assert_eq!(store.close_open_spans()?, 2);

    let spans = store.spans_in_range(0, i64::MAX)?;
    let ended = |id: i64| {
        spans
            .iter()
            .find(|span| span.id == id)
            .and_then(|span| span.ended_at)
    };
    // A span that started before the newest frame ends there; one that started
    // after it keeps its own start.
    assert_eq!(ended(before), Some(1_000));
    assert_eq!(ended(after), Some(5_000));
    assert_eq!(ended(closed), Some(200));
    // Nothing left to close on a second call.
    assert_eq!(store.close_open_spans()?, 0);
    Ok(())
}

#[test]
fn close_open_spans_uses_the_start_when_no_frame_exists() -> TestResult {
    let (_dir, store) = open_store()?;
    let span = store.begin_span("com.example.Idle", "Idle", None, None, 700)?;

    assert_eq!(store.close_open_spans()?, 1);

    let spans = store.spans_in_range(0, 1_000)?;
    assert_eq!(spans.len(), 1);
    assert_eq!(spans[0].id, span);
    assert_eq!(spans[0].ended_at, Some(700));
    Ok(())
}
