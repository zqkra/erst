//! Line sources: OCR text, accessibility text, and searchable window titles.

mod common;

use common::{
    APP, APP_NAME, TestResult, begin_segment, frame, line, open_store, search_params, simple_frame,
};
use erst_store::{LineSource, Store};

const TITLE: &str = "Quarterly budget review";

/// Writes one frame whose title is [`TITLE`] and whose only line is `text`.
fn titled_frame(store: &Store, segment_id: i64, captured_at: i64, text: &str) -> TestResult {
    store.insert_frame(&frame(
        segment_id,
        captured_at,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![line(text, 0)],
    ))?;
    Ok(())
}

#[test]
fn a_frame_keeps_the_source_of_every_line() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let mut exact = line("read from the accessibility tree", 1);
    exact.source = LineSource::Accessibility;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        None,
        vec![line("read from the pixels", 0), exact],
    ))?;

    let lines = store.frame_detail(frame_id)?.lines;
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].text, "read from the pixels");
    assert_eq!(lines[0].source, LineSource::Ocr);
    assert_eq!(lines[1].text, "read from the accessibility tree");
    assert_eq!(lines[1].source, LineSource::Accessibility);
    Ok(())
}

#[test]
fn a_word_only_in_the_window_title_finds_the_frame() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![line("unrelated body text", 0)],
    ))?;

    let hits = store.search(&search_params("quarterly", 10))?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, frame_id);
    assert_eq!(hits[0].matched_lines.len(), 1);
    let title = &hits[0].matched_lines[0];
    assert_eq!(title.text, TITLE);
    assert_eq!(title.source, LineSource::Title);
    assert_eq!((title.x, title.y, title.w, title.h), (0, 0, 0, 0));
    Ok(())
}

#[test]
fn a_moment_leaves_the_title_line_out_of_its_text() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![line("unrelated body text", 0)],
    ))?;

    let detail = store.frame_detail(frame_id)?;
    assert_eq!(detail.lines.len(), 1);
    assert_eq!(detail.lines[0].text, "unrelated body text");
    assert!(
        detail
            .lines
            .iter()
            .all(|line| line.source != LineSource::Title),
        "the moment names its window from frames.window_title"
    );
    let hits = store.search(&search_params("quarterly", 10))?;
    assert_eq!(hits[0].window_title.as_deref(), Some(TITLE));
    Ok(())
}

#[test]
fn a_title_equal_to_a_line_of_the_frame_is_still_searchable() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&frame(
        segment_id,
        1_000,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![line(TITLE, 3), line("other text", 4)],
    ))?;

    assert_eq!(store.frame_detail(frame_id)?.lines.len(), 2);
    let hits = store.search(&search_params("quarterly", 10))?;
    assert_eq!(hits.len(), 1);
    // The title line sits at (0, 0) and the frame's own copy lower down, so
    // the key holds both rows.
    assert_eq!(hits[0].matched_lines.len(), 2);
    assert_eq!(hits[0].matched_lines[0].source, LineSource::Title);
    assert_eq!(hits[0].matched_lines[1].source, LineSource::Ocr);
    Ok(())
}

#[test]
fn erasing_a_frame_drops_its_title_line() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&simple_frame(segment_id, 1_000, &["body text"]))?;
    assert_eq!(store.search(&search_params("window", 10))?.len(), 1);

    let outcome = store.erase_range(0, 2_000)?;
    assert_eq!(outcome.frames_removed, 1);
    assert_eq!(
        store.search(&search_params("window", 10))?.len(),
        0,
        "the title line went with its frame"
    );
    assert_eq!(store.storage_stats(1_500)?.unique_line_count, 0);
    assert!(store.frame_detail(frame_id).is_err());
    Ok(())
}

#[test]
fn erasing_one_frame_keeps_a_title_line_another_frame_uses() -> TestResult {
    let (_dir, store) = open_store()?;
    let first_segment = store.begin_segment("segments/first.mp4", 0, 1_920, 1_080)?;
    store.finish_segment(first_segment, 1_000, 10)?;
    let second_segment = store.begin_segment("segments/second.mp4", 2_000, 1_920, 1_080)?;
    store.finish_segment(second_segment, 3_000, 10)?;
    titled_frame(&store, first_segment, 500, "first body")?;
    let kept = store.insert_frame(&frame(
        second_segment,
        2_500,
        APP,
        APP_NAME,
        Some(TITLE),
        vec![line("second body", 0)],
    ))?;

    store.erase_range(0, 1_500)?;

    let hits = store.search(&search_params("quarterly", 10))?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, kept);
    assert_eq!(hits[0].matched_lines[0].source, LineSource::Title);
    Ok(())
}
