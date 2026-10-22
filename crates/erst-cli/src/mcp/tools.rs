//! Tool implementations: every tool answers with text and never touches images.

use erst_core::query;
use erst_core::time::{TimeRange, local_day_of_text};
use erst_store::{SearchParams, Store, StoreError};
use serde_json::Value;

use super::protocol::{RpcError, ToolResult};
use super::{render, window};
use crate::activity::ActivityReport;
use crate::format;

/// Smallest `limit` a search accepts.
pub const MIN_SEARCH_LIMIT: u32 = 1;
/// Moments returned when the caller does not ask for a limit.
pub const DEFAULT_SEARCH_LIMIT: u32 = 10;
/// Hard ceiling so one call cannot scan the whole history.
pub const MAX_SEARCH_LIMIT: u32 = 50;

/// Dispatches one `tools/call` request.
///
/// A bad argument is a tool result with `isError: true`, not a protocol error,
/// so the model can read the message and correct its call. The MCP
/// specification (tools, error handling, revision 2025-06-18) asks for this.
/// Only an unknown tool name or a call without a name is a JSON-RPC error.
pub fn call(store: &Store, params: &Value, now_ms: i64) -> Result<ToolResult, RpcError> {
    let name = params
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| RpcError::invalid_params("tools/call needs a tool name"))?;
    let empty = Value::Object(serde_json::Map::new());
    let arguments = match params.get("arguments") {
        None | Some(Value::Null) => &empty,
        Some(value) => value,
    };
    if !arguments.is_object() {
        return Ok(ToolResult::error(format!(
            "{name} expects an object of arguments."
        )));
    }
    match name {
        "search_screen_history" => Ok(search(store, arguments, now_ms)),
        "get_moment" => Ok(moment(store, arguments, now_ms)),
        "activity_summary" => Ok(activity(store, arguments, now_ms)),
        other => Err(RpcError::invalid_params(format!("unknown tool: {other}"))),
    }
}

fn history_window(store: &Store) -> Result<window::HistoryWindow, ToolResult> {
    window::history_window(store).map_err(|error| ToolResult::error(format!("{error:#}")))
}

fn search(store: &Store, args: &Value, now_ms: i64) -> ToolResult {
    let Some(query_text) = args.get("query").and_then(Value::as_str) else {
        return ToolResult::error("search_screen_history needs a \"query\" string.");
    };
    if query_text.trim().is_empty() {
        return ToolResult::error("search_screen_history needs a non-empty \"query\".");
    }
    let limit = match search_limit(args) {
        Ok(limit) => limit,
        Err(message) => return ToolResult::error(message),
    };
    let history = match history_window(store) {
        Ok(history) => history,
        Err(error) => return error,
    };
    let parsed = query::parse(query_text, now_ms, format::utc_offset_ms);
    let Some(fts_match) = parsed.fts_match() else {
        return ToolResult::error(
            "search_screen_history needs words to search for; app: and date tokens only narrow a text query.",
        );
    };
    let cutoff_ms = history.cutoff_ms(now_ms);
    let since_ms = match (parsed.since_ms, cutoff_ms) {
        (Some(since), Some(cutoff)) => Some(since.max(cutoff)),
        (since, cutoff) => since.or(cutoff),
    };
    let params = SearchParams {
        fts_match,
        app: parsed.app,
        since_ms,
        until_ms: parsed.until_ms,
        limit,
    };
    let hits = match store.search(&params) {
        Ok(hits) => hits,
        Err(error) => {
            return ToolResult::error(format!("Could not search the screen history: {error}"));
        }
    };
    ToolResult::text(render::hits(query_text, &hits, history.days))
}

fn moment(store: &Store, args: &Value, now_ms: i64) -> ToolResult {
    let Some(frame_id) = args.get("frame_id").and_then(Value::as_i64) else {
        return ToolResult::error(
            "get_moment needs an integer \"frame_id\" from search_screen_history.",
        );
    };
    if frame_id <= 0 {
        return ToolResult::error("frame_id must be a positive integer.");
    }
    let history = match history_window(store) {
        Ok(history) => history,
        Err(error) => return error,
    };
    let detail = match store.frame_detail(frame_id) {
        Ok(detail) => detail,
        Err(StoreError::NotFound { .. }) => {
            return ToolResult::error(format!(
                "No moment with frame_id {frame_id}. Search first with search_screen_history."
            ));
        }
        Err(error) => {
            return ToolResult::error(format!("Could not read moment {frame_id}: {error}"));
        }
    };
    if let Some(cutoff_ms) = history.cutoff_ms(now_ms)
        && detail.stamp.captured_at < cutoff_ms
    {
        return ToolResult::error(format!(
            "Moment {frame_id} is older than the agent history window ({} days).",
            history.days.unwrap_or(0)
        ));
    }
    ToolResult::text(render::moment(&detail))
}

fn activity(store: &Store, args: &Value, now_ms: i64) -> ToolResult {
    let day = match args.get("day") {
        None | Some(Value::Null) => match format::local_date(now_ms) {
            Some(day) => day,
            None => return ToolResult::error("Could not read the local date."),
        },
        Some(Value::String(day)) => day.clone(),
        Some(_) => return ToolResult::error("day must be a YYYY-MM-DD string."),
    };
    let Some(range) = local_day_of_text(&day, format::utc_offset_ms) else {
        return ToolResult::error(format!("Invalid day {day:?}; expected YYYY-MM-DD."));
    };
    let history = match history_window(store) {
        Ok(history) => history,
        Err(error) => return error,
    };
    let cutoff_ms = history.cutoff_ms(now_ms);
    if let Some(cutoff_ms) = cutoff_ms
        && range.end_ms <= cutoff_ms
    {
        return ToolResult::error(format!(
            "Activity for {day} is older than the agent history window ({} days).",
            history.days.unwrap_or(0)
        ));
    }
    let clipped = TimeRange {
        start_ms: cutoff_ms.map_or(range.start_ms, |cutoff_ms| range.start_ms.max(cutoff_ms)),
        end_ms: range.end_ms,
    };
    let report = match ActivityReport::load(store, &day, clipped, now_ms) {
        Ok(report) => report,
        Err(error) => {
            return ToolResult::error(format!("Could not summarize activity for {day}: {error:#}"));
        }
    };
    ToolResult::text(format!(
        "{}{}",
        crate::activity::summary_text(&report),
        render::limit_note(history.days)
    ))
}

/// Validates and clamps the optional `limit` argument.
fn search_limit(args: &Value) -> Result<u32, String> {
    match args.get("limit") {
        None | Some(Value::Null) => Ok(DEFAULT_SEARCH_LIMIT),
        Some(value) => match value.as_u64() {
            Some(value) if value >= u64::from(MIN_SEARCH_LIMIT) => {
                Ok(u32::try_from(value.min(u64::from(MAX_SEARCH_LIMIT)))
                    .unwrap_or(MAX_SEARCH_LIMIT))
            }
            _ => Err(format!(
                "limit must be an integer between {MIN_SEARCH_LIMIT} and {MAX_SEARCH_LIMIT}."
            )),
        },
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use serde_json::json;

    use super::{DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT, search_limit};

    #[test]
    fn limit_defaults_to_ten() {
        assert_eq!(
            search_limit(&json!({"query": "zebra"})).unwrap(),
            DEFAULT_SEARCH_LIMIT
        );
        assert_eq!(
            search_limit(&json!({"limit": null})).unwrap(),
            DEFAULT_SEARCH_LIMIT
        );
    }

    #[test]
    fn limit_is_clamped_to_fifty() {
        assert_eq!(
            search_limit(&json!({"limit": 500})).unwrap(),
            MAX_SEARCH_LIMIT
        );
        assert_eq!(search_limit(&json!({"limit": 7})).unwrap(), 7);
    }

    #[test]
    fn limit_rejects_zero_and_non_integers() {
        assert!(search_limit(&json!({"limit": 0})).is_err());
        assert!(search_limit(&json!({"limit": "7"})).is_err());
        assert!(search_limit(&json!({"limit": -1})).is_err());
    }
}
