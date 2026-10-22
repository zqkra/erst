//! Line sources crossing the FFI boundary.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::{open_engine, text_line};
use erst_ffi::{FfiLineSource, FfiNewFrame};

type TestResult = Result<(), Box<dyn std::error::Error>>;

const SAFARI: &str = "com.apple.Safari";

#[test]
fn a_recorded_accessibility_line_comes_back_from_search_with_its_source() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment_id = engine.begin_segment("segments/a.mp4".to_owned(), 0, 1_920, 1_080)?;
    let mut line = text_line("quarterly budget review", 200);
    line.source = FfiLineSource::Accessibility;
    let frame = FfiNewFrame {
        captured_at_ms: 1_000,
        segment_id,
        pts_ms: 0,
        bundle_id: SAFARI.to_owned(),
        app_name: "Safari".to_owned(),
        window_title: Some("Notes".to_owned()),
        url: None,
        change_ratio: 0.5,
        lines: vec![line],
    };
    engine.record_frame(frame)?;

    let hits = engine.search("quarterly".to_owned(), 10, "UTC".to_owned())?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].matched_lines.len(), 1);
    assert_eq!(
        hits[0].matched_lines[0].source,
        FfiLineSource::Accessibility
    );
    Ok(())
}

#[test]
fn a_title_line_from_the_app_is_stored_as_ocr() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment_id = engine.begin_segment("segments/b.mp4".to_owned(), 0, 1_920, 1_080)?;
    let mut line = text_line("quarterly budget review", 200);
    line.source = FfiLineSource::Title;
    let frame = FfiNewFrame {
        captured_at_ms: 1_000,
        segment_id,
        pts_ms: 0,
        bundle_id: SAFARI.to_owned(),
        app_name: "Safari".to_owned(),
        window_title: Some("Budget".to_owned()),
        url: None,
        change_ratio: 0.5,
        lines: vec![line],
    };
    engine.record_frame(frame)?;

    let hits = engine.search("quarterly".to_owned(), 10, "UTC".to_owned())?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].matched_lines.len(), 1);
    assert_eq!(hits[0].matched_lines[0].source, FfiLineSource::Ocr);
    let moment = engine.moment(hits[0].frame_id, "UTC".to_owned())?;
    assert_eq!(moment.lines.len(), 1);
    assert_eq!(moment.lines[0].source, FfiLineSource::Ocr);
    Ok(())
}
