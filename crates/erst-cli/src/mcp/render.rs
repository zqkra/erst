//! Text blocks returned by MCP tools. Text only, never images.

use std::fmt::Write as _;

use erst_store::{FrameDetail, LineBox, SearchHit};

use crate::format;

/// Appended when the user's agent history window narrowed the answer.
pub fn limit_note(days: Option<u32>) -> String {
    match days {
        Some(days) => {
            format!("\nLimited to the last {days} days by the Erst agent history setting.")
        }
        None => String::new(),
    }
}

fn present(value: Option<&str>) -> Option<&str> {
    value.filter(|text| !text.trim().is_empty())
}

/// The window, URL, and frame id lines that every moment block starts with.
fn write_context(block: &mut String, window_title: Option<&str>, url: Option<&str>, frame_id: i64) {
    if let Some(title) = present(window_title) {
        let _ = write!(block, "\nwindow: {}", title.trim());
    }
    if let Some(url) = present(url) {
        let _ = write!(block, "\nurl: {}", url.trim());
    }
    let _ = write!(block, "\nframe_id: {frame_id}");
}

/// One block per matched moment.
pub fn hits(query: &str, hits: &[SearchHit], days: Option<u32>) -> String {
    let mut blocks = Vec::with_capacity(hits.len());
    for hit in hits {
        let mut block = format!("{}  {}", format::iso_local(hit.captured_at), hit.app_name);
        write_context(
            &mut block,
            hit.window_title.as_deref(),
            hit.url.as_deref(),
            hit.frame_id,
        );
        if hit.matched_lines.is_empty() {
            block.push_str("\nmatched: (none)");
        } else {
            block.push_str("\nmatched:");
            for line in &hit.matched_lines {
                let _ = write!(block, "\n  {}", line.text.trim());
            }
        }
        blocks.push(block);
    }
    let mut text = if blocks.is_empty() {
        format!("No moments matched {query:?}.")
    } else {
        blocks.join("\n\n")
    };
    text.push_str(&limit_note(days));
    text
}

/// The whole moment with its lines in reading order.
pub fn moment(detail: &FrameDetail) -> String {
    let mut text = format::iso_local(detail.stamp.captured_at);
    let _ = write!(text, "\napp: {}", detail.app_name);
    write_context(
        &mut text,
        detail.window_title.as_deref(),
        detail.url.as_deref(),
        detail.stamp.id,
    );
    let mut lines: Vec<&LineBox> = detail.lines.iter().collect();
    lines.sort_by_key(|line| (line.y, line.x));
    if lines.is_empty() {
        text.push_str("\nlines: (no text)");
    } else {
        text.push_str("\nlines:");
        for line in lines {
            let _ = write!(text, "\n  {}", line.text.trim());
        }
    }
    text
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use erst_store::{FrameDetail, FrameStamp, LineBox, LineSource, SearchHit};

    use super::{hits, limit_note, moment};

    fn line(text: &str, x: u16, y: u16) -> LineBox {
        LineBox {
            text: String::from(text),
            x,
            y,
            w: 10,
            h: 10,
            source: LineSource::Ocr,
        }
    }

    fn hit(app: &str) -> SearchHit {
        SearchHit {
            frame_id: 9,
            captured_at: 1_792_029_600_000,
            first_seen_ms: 1_792_029_600_000,
            last_seen_ms: 1_792_029_600_000,
            bundle_id: String::from("com.example.App"),
            app_name: String::from(app),
            window_title: Some(String::from("Docs")),
            url: Some(String::from("https://example.com/a")),
            segment_path: None,
            pts_ms: 0,
            matched_lines: vec![line("the zebra crossing", 10, 20)],
        }
    }

    fn detail(lines: Vec<LineBox>) -> FrameDetail {
        FrameDetail {
            stamp: FrameStamp {
                id: 9,
                captured_at: 1_792_029_600_000,
                change_ratio: 0.1,
            },
            bundle_id: String::from("com.example.App"),
            app_name: String::from("Safari"),
            window_title: Some(String::from("Docs")),
            url: Some(String::from("https://example.com/a")),
            segment_id: 1,
            segment_path: Some(String::from("segments/1.mp4")),
            segment_started_at: 1_792_029_000_000,
            pts_ms: 0,
            tier: 0,
            lines,
        }
    }

    #[test]
    fn hits_include_time_app_title_url_lines_and_frame_id() {
        let text = hits("zebra", &[hit("Safari")], None);
        assert!(text.contains("Safari"));
        assert!(text.contains("window: Docs"));
        assert!(text.contains("url: https://example.com/a"));
        assert!(text.contains("frame_id: 9"));
        assert!(text.contains("the zebra crossing"));
        assert!(text.contains('T'));
        assert!(!text.contains("Limited to the last"));
    }

    #[test]
    fn empty_hits_say_what_was_searched() {
        assert_eq!(hits("zebra", &[], None), "No moments matched \"zebra\".");
    }

    #[test]
    fn a_window_is_named_in_the_answer() {
        assert_eq!(
            limit_note(Some(7)),
            "\nLimited to the last 7 days by the Erst agent history setting."
        );
        assert_eq!(limit_note(None), "");
    }

    #[test]
    fn moment_lines_are_sorted_by_y_then_x() {
        let text = moment(&detail(vec![
            line("bottom right", 900, 500),
            line("top right", 900, 100),
            line("top left", 100, 100),
        ]));
        let top_left = text.find("top left").unwrap();
        let top_right = text.find("top right").unwrap();
        let bottom_right = text.find("bottom right").unwrap();
        assert!(top_left < top_right);
        assert!(top_right < bottom_right);
    }

    #[test]
    fn moment_without_lines_says_so() {
        let text = moment(&detail(Vec::new()));
        assert!(text.contains("lines: (no text)"));
        assert!(text.contains("app: Safari"));
        assert!(text.contains("frame_id: 9"));
    }
}
