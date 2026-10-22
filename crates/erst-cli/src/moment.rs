//! `erst moment`: every text line of one moment, in reading order.

use std::io::Write;

use anyhow::{Context, Result, bail};
use erst_store::{FrameDetail, LineBox, Store, StoreError};
use serde::Serialize;

use crate::cli::MomentArgs;
use crate::format;
use crate::mcp::render;
use crate::window;

/// Reads one moment inside the agent history window and writes the requested format.
pub fn run(store: &Store, args: &MomentArgs, now_ms: i64, out: &mut impl Write) -> Result<()> {
    let history = window::history_window(store)?;
    let detail = match store.frame_detail(args.frame_id) {
        Ok(detail) => detail,
        Err(StoreError::NotFound { .. }) => bail!(
            "no moment with frame_id {}; find one with `erst search`",
            args.frame_id
        ),
        Err(error) => {
            return Err(error).with_context(|| format!("could not read moment {}", args.frame_id));
        }
    };
    if !history.allows(detail.stamp.captured_at, now_ms) {
        bail!(
            "moment {} is older than the agent history window ({} days); widen it in Erst, Settings, Agents",
            args.frame_id,
            history.days.unwrap_or(0)
        );
    }
    if args.json {
        write_json(&detail, out)
    } else {
        writeln!(out, "{}", render::moment(&detail))?;
        Ok(())
    }
}

/// One moment as JSON, its lines already in reading order so consumers never sort boxes.
#[derive(Debug, Serialize)]
struct JsonMoment<'a> {
    frame_id: i64,
    captured_at: i64,
    time: String,
    bundle_id: &'a str,
    app: &'a str,
    window_title: Option<&'a str>,
    url: Option<&'a str>,
    lines: Vec<&'a str>,
}

fn write_json(detail: &FrameDetail, out: &mut impl Write) -> Result<()> {
    let mut lines: Vec<&LineBox> = detail.lines.iter().collect();
    lines.sort_by_key(|line| (line.y, line.x));
    let moment = JsonMoment {
        frame_id: detail.stamp.id,
        captured_at: detail.stamp.captured_at,
        time: format::iso_local(detail.stamp.captured_at),
        bundle_id: &detail.bundle_id,
        app: &detail.app_name,
        window_title: detail.window_title.as_deref(),
        url: detail.url.as_deref(),
        lines: lines.iter().map(|line| line.text.trim()).collect(),
    };
    serde_json::to_writer_pretty(&mut *out, &moment)?;
    writeln!(out)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use erst_store::{FrameDetail, FrameStamp, LineBox, LineSource};
    use serde_json::Value;

    use super::write_json;

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

    fn detail(lines: Vec<LineBox>) -> FrameDetail {
        FrameDetail {
            stamp: FrameStamp {
                id: 42,
                captured_at: 1_792_029_600_000,
                change_ratio: 0.1,
            },
            bundle_id: String::from("com.apple.Safari"),
            app_name: String::from("Safari"),
            window_title: Some(String::from("Pinning in practice")),
            url: Some(String::from("https://doc.rust-lang.org/")),
            segment_id: 1,
            segment_path: None,
            segment_started_at: 0,
            pts_ms: 0,
            tier: 0,
            lines,
        }
    }

    #[test]
    fn json_moment_lists_lines_in_reading_order() {
        let mut out = Vec::new();
        let lines = vec![
            line("second row", 5, 20),
            line("first row, right", 30, 10),
            line("first row", 5, 10),
        ];
        write_json(&detail(lines), &mut out).unwrap();
        let value: Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["frame_id"], 42);
        assert_eq!(value["app"], "Safari");
        assert_eq!(value["url"], "https://doc.rust-lang.org/");
        let lines: Vec<&str> = value["lines"]
            .as_array()
            .unwrap()
            .iter()
            .map(|line| line.as_str().unwrap())
            .collect();
        assert_eq!(lines, vec!["first row", "first row, right", "second row"]);
    }

    #[test]
    fn json_moment_without_lines_has_an_empty_list() {
        let mut out = Vec::new();
        write_json(&detail(Vec::new()), &mut out).unwrap();
        let value: Value = serde_json::from_slice(&out).unwrap();
        assert_eq!(value["lines"], serde_json::json!([]));
        assert!(value["window_title"].is_string());
    }
}
