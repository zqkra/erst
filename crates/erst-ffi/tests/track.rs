//! The timeline track call: one range turned into frames and app and site
//! segments, ready for the frame-indexed scrubber.

#![allow(clippy::unwrap_used, clippy::expect_used)] // the shared test helpers unwrap

mod common;

use common::{open_engine, text_line};
use erst_ffi::{Engine, FfiNewFrame, FfiTrackSegment};

type TestResult = Result<(), Box<dyn std::error::Error>>;

const SAFARI: &str = "com.apple.Safari";
const XCODE: &str = "com.apple.dt.Xcode";
const MINUTE: i64 = 60_000;

/// 2023-11-14T22:13:20Z, far from the clock the engine reads on open.
const BASE_MS: i64 = 1_700_000_000_000;

#[allow(clippy::too_many_arguments)]
fn frame(
    segment_id: i64,
    at_ms: i64,
    bundle_id: &str,
    app_name: &str,
    window_title: Option<&str>,
    url: Option<&str>,
    change_ratio: f32,
) -> FfiNewFrame {
    FfiNewFrame {
        captured_at_ms: at_ms,
        segment_id,
        pts_ms: 0,
        bundle_id: bundle_id.to_owned(),
        app_name: app_name.to_owned(),
        window_title: window_title.map(str::to_owned),
        url: url.map(str::to_owned),
        change_ratio,
        lines: vec![text_line("track", 200)],
    }
}

fn record(engine: &Engine, frames: &[FfiNewFrame]) -> Result<Vec<i64>, Box<dyn std::error::Error>> {
    let mut ids = Vec::with_capacity(frames.len());
    for new_frame in frames {
        ids.push(engine.record_frame(new_frame.clone())?);
    }
    Ok(ids)
}

/// The fields of a segment the track test asserts.
#[derive(Debug, PartialEq)]
struct SegmentShape {
    bundle_id: String,
    app_name: String,
    title: Option<String>,
    host: Option<String>,
    first_frame: u32,
    last_frame: u32,
    starts_session: bool,
}

fn shape(
    bundle_id: &str,
    app_name: &str,
    title: Option<&str>,
    host: Option<&str>,
    frames: (u32, u32),
    starts_session: bool,
) -> SegmentShape {
    SegmentShape {
        bundle_id: bundle_id.to_owned(),
        app_name: app_name.to_owned(),
        title: title.map(str::to_owned),
        host: host.map(str::to_owned),
        first_frame: frames.0,
        last_frame: frames.1,
        starts_session,
    }
}

fn segment_shape(segment: &FfiTrackSegment) -> SegmentShape {
    SegmentShape {
        bundle_id: segment.bundle_id.clone(),
        app_name: segment.app_name.clone(),
        title: segment.title.clone(),
        host: segment.host.clone(),
        first_frame: segment.first_frame,
        last_frame: segment.last_frame,
        starts_session: segment.starts_session,
    }
}

#[test]
fn timeline_track_groups_frames_into_app_and_site_segments() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment_id = engine.begin_segment("segments/track.mp4".to_owned(), BASE_MS, 1920, 1080)?;
    let frames = [
        frame(
            segment_id,
            BASE_MS,
            SAFARI,
            "Safari",
            Some("Example Domain"),
            Some("https://example.com/a"),
            0.40,
        ),
        // The title changes inside the segment: the track labels it with the one
        // the user saw last.
        frame(
            segment_id,
            BASE_MS + 30_000,
            SAFARI,
            "Safari",
            Some("Example Domain: page b"),
            Some("https://www.example.com/b"),
            0.25,
        ),
        frame(
            segment_id,
            BASE_MS + MINUTE,
            XCODE,
            "Xcode",
            Some("Erst"),
            None,
            0.80,
        ),
        frame(
            segment_id,
            BASE_MS + 2 * MINUTE,
            XCODE,
            "Xcode",
            Some("  encoder.rs  "),
            None,
            0.10,
        ),
        // Ten minutes and one millisecond later: a new session on the same app.
        frame(
            segment_id,
            BASE_MS + 12 * MINUTE + 1,
            XCODE,
            "Xcode",
            Some("   "),
            None,
            0.55,
        ),
        frame(
            segment_id,
            BASE_MS + 13 * MINUTE,
            SAFARI,
            "Safari",
            None,
            Some("https://news.ycombinator.com/item?id=1"),
            0.30,
        ),
        // A frame whose app row has neither a bundle id nor a name.
        frame(segment_id, BASE_MS + 14 * MINUTE, "", "", None, None, 0.05),
    ];
    let ids = record(&engine, &frames)?;

    let track = engine.timeline_track(BASE_MS, BASE_MS + 60 * MINUTE)?;
    assert_eq!(track.start_ms, BASE_MS);
    assert_eq!(track.end_ms, BASE_MS + 60 * MINUTE);
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.id)
            .collect::<Vec<_>>(),
        ids
    );
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.captured_at_ms)
            .collect::<Vec<_>>(),
        frames
            .iter()
            .map(|new| new.captured_at_ms)
            .collect::<Vec<_>>()
    );
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.change_ratio)
            .collect::<Vec<_>>(),
        frames
            .iter()
            .map(|new| new.change_ratio)
            .collect::<Vec<_>>()
    );
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.segment)
            .collect::<Vec<_>>(),
        vec![0, 0, 1, 1, 2, 3, 4]
    );

    let shapes: Vec<_> = track.segments.iter().map(segment_shape).collect();
    assert_eq!(
        shapes,
        vec![
            shape(
                SAFARI,
                "Safari",
                Some("Example Domain: page b"),
                Some("example.com"),
                (0, 1),
                true
            ),
            shape(XCODE, "Xcode", Some("encoder.rs"), None, (2, 3), false),
            // A title of whitespace only is no title.
            shape(XCODE, "Xcode", None, None, (4, 4), true),
            shape(
                SAFARI,
                "Safari",
                None,
                Some("news.ycombinator.com"),
                (5, 5),
                false
            ),
            shape("", "Unknown", None, None, (6, 6), false),
        ]
    );
    assert_eq!(track.segments[0].started_at_ms, BASE_MS);
    assert_eq!(track.segments[0].ended_at_ms, BASE_MS + 30_000);
    assert_eq!(track.segments[2].started_at_ms, BASE_MS + 12 * MINUTE + 1);
    assert_eq!(track.segments[4].ended_at_ms, BASE_MS + 14 * MINUTE);
    Ok(())
}

#[test]
fn timeline_track_indexes_into_the_frames_of_its_own_range() -> TestResult {
    let (_temp, _data_dir, engine) = open_engine();
    let segment_id = engine.begin_segment("segments/range.mp4".to_owned(), BASE_MS, 1920, 1080)?;
    let frames = [
        frame(segment_id, BASE_MS, SAFARI, "Safari", Some("A"), None, 0.2),
        frame(
            segment_id,
            BASE_MS + MINUTE,
            XCODE,
            "Xcode",
            Some("B"),
            None,
            0.4,
        ),
        frame(
            segment_id,
            BASE_MS + 2 * MINUTE,
            SAFARI,
            "Safari",
            Some("C"),
            None,
            0.6,
        ),
        frame(
            segment_id,
            BASE_MS + 3 * MINUTE,
            XCODE,
            "Xcode",
            Some("D"),
            None,
            0.8,
        ),
    ];
    let ids = record(&engine, &frames)?;

    let track = engine.timeline_track(BASE_MS + MINUTE, BASE_MS + 3 * MINUTE)?;
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.id)
            .collect::<Vec<_>>(),
        ids[1..3].to_vec()
    );
    assert_eq!(
        track
            .frames
            .iter()
            .map(|known| known.segment)
            .collect::<Vec<_>>(),
        vec![0, 1]
    );
    assert_eq!(
        track
            .segments
            .iter()
            .map(|segment| (segment.first_frame, segment.last_frame))
            .collect::<Vec<_>>(),
        vec![(0, 0), (1, 1)]
    );
    assert_eq!(
        track
            .segments
            .iter()
            .map(|segment| segment.title.as_deref())
            .collect::<Vec<_>>(),
        vec![Some("B"), Some("C")]
    );
    let empty = engine.timeline_track(BASE_MS + 4 * MINUTE, BASE_MS + 5 * MINUTE)?;
    assert!(empty.frames.is_empty());
    assert!(empty.segments.is_empty());
    Ok(())
}
