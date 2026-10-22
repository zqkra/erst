#![allow(clippy::unwrap_used, clippy::expect_used, clippy::assert_is_empty)]

use super::{SESSION_GAP_MS, SegmentKey, TrackSegment, group_segments, url_host};

fn app(bundle_id: &str) -> SegmentKey {
    SegmentKey {
        bundle_id: String::from(bundle_id),
        host: None,
    }
}

fn site(host: &str) -> SegmentKey {
    SegmentKey {
        bundle_id: String::from("com.apple.Safari"),
        host: Some(String::from(host)),
    }
}

fn browser(url: &str) -> SegmentKey {
    SegmentKey {
        bundle_id: String::from("com.apple.Safari"),
        host: url_host(url),
    }
}

fn indexes(segments: &[TrackSegment]) -> Vec<(usize, usize)> {
    segments
        .iter()
        .map(|segment| (segment.first_index, segment.last_index))
        .collect()
}

#[test]
fn no_frames_make_no_segments() {
    assert!(group_segments(&[]).is_empty());
}

#[test]
fn one_frame_is_one_segment_that_starts_a_session() {
    let segments = group_segments(&[(1_000, app("com.apple.dt.Xcode"))]);
    assert_eq!(segments.len(), 1);
    assert_eq!(segments[0].first_index, 0);
    assert_eq!(segments[0].last_index, 0);
    assert_eq!(segments[0].started_at_ms, 1_000);
    assert_eq!(segments[0].ended_at_ms, 1_000);
    assert!(segments[0].starts_session);
}

#[test]
fn alternating_apps_make_one_segment_per_run() {
    let frames = [
        (0, app("com.apple.Safari")),
        (1_000, app("com.apple.dt.Xcode")),
        (2_000, app("com.apple.Safari")),
        (3_000, app("com.apple.Safari")),
    ];
    let segments = group_segments(&frames);
    assert_eq!(indexes(&segments), vec![(0, 0), (1, 1), (2, 3)]);
    assert_eq!(
        segments
            .iter()
            .map(|segment| segment.starts_session)
            .collect::<Vec<_>>(),
        vec![true, false, false]
    );
    assert_eq!(segments[2].started_at_ms, 2_000);
    assert_eq!(segments[2].ended_at_ms, 3_000);
}

#[test]
fn a_pause_of_exactly_the_gap_stays_in_one_segment() {
    let frames = [
        (0, app("com.apple.dt.Xcode")),
        (SESSION_GAP_MS, app("com.apple.dt.Xcode")),
    ];
    let segments = group_segments(&frames);
    assert_eq!(indexes(&segments), vec![(0, 1)]);
    assert!(segments[0].starts_session);
    assert_eq!(segments[0].ended_at_ms, SESSION_GAP_MS);
}

#[test]
fn a_pause_one_millisecond_past_the_gap_starts_a_session() {
    let frames = [
        (0, app("com.apple.dt.Xcode")),
        (SESSION_GAP_MS + 1, app("com.apple.dt.Xcode")),
    ];
    let segments = group_segments(&frames);
    assert_eq!(indexes(&segments), vec![(0, 0), (1, 1)]);
    assert_eq!(
        segments
            .iter()
            .map(|segment| segment.starts_session)
            .collect::<Vec<_>>(),
        vec![true, true]
    );
}

#[test]
fn browser_frames_on_two_hosts_make_two_segments() {
    let frames = [
        (0, site("example.com")),
        (2_000, site("example.com")),
        (4_000, site("news.ycombinator.com")),
    ];
    let segments = group_segments(&frames);
    assert_eq!(indexes(&segments), vec![(0, 1), (2, 2)]);
    assert_eq!(segments[0].key.host.as_deref(), Some("example.com"));
    assert_eq!(
        segments[1].key.host.as_deref(),
        Some("news.ycombinator.com")
    );
    assert!(!segments[1].starts_session);
}

#[test]
fn the_same_host_on_different_paths_stays_one_segment() {
    let frames = [
        (0, browser("https://example.com/one")),
        (3_000, browser("https://www.example.com/two?q=1")),
    ];
    let segments = group_segments(&frames);
    assert_eq!(indexes(&segments), vec![(0, 1)]);
    assert_eq!(segments[0].key.host.as_deref(), Some("example.com"));
}

#[test]
fn url_host_is_lowercase_without_scheme_port_or_www() {
    assert_eq!(
        url_host("https://Example.COM:8443/path?q=1#frag").as_deref(),
        Some("example.com")
    );
    assert_eq!(
        url_host("HTTP://WWW.Example.com").as_deref(),
        Some("example.com")
    );
    assert_eq!(
        url_host("https://user:pass@example.com:443/x").as_deref(),
        Some("example.com")
    );
    assert_eq!(url_host("https://[::1]:8080/x").as_deref(), Some("::1"));
    assert_eq!(
        url_host("https://[2001:db8::1]/x").as_deref(),
        Some("2001:db8::1")
    );
    assert_eq!(url_host("example.com/path").as_deref(), Some("example.com"));
    assert_eq!(
        url_host("example.com:8443/path").as_deref(),
        Some("example.com")
    );
}

#[test]
fn url_host_is_none_without_a_web_site() {
    assert_eq!(url_host(""), None);
    assert_eq!(url_host("   "), None);
    assert_eq!(url_host("https://"), None);
    assert_eq!(url_host("www."), None);
    assert_eq!(url_host("file:///Users/me/Desktop"), None);
    assert_eq!(url_host("about:blank"), None);
    assert_eq!(url_host("mailto:someone@example.com"), None);
    assert_eq!(url_host("ftp://example.com/x"), None);
    assert_eq!(url_host("localhost:3000/x"), None);
    assert_eq!(url_host("http:/example.com"), None);
}
