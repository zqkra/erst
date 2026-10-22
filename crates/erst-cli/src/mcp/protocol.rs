//! JSON-RPC 2.0 envelopes and the MCP payloads this server understands.

use serde_json::{Value, json};

use super::tools::{DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT, MIN_SEARCH_LIMIT};

pub const JSONRPC_VERSION: &str = "2.0";
pub const SERVER_NAME: &str = "erst";
pub const LATEST_PROTOCOL_VERSION: &str = "2025-11-25";
pub const SUPPORTED_PROTOCOL_VERSIONS: [&str; 4] =
    ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];

pub const PARSE_ERROR: i32 = -32700;
pub const INVALID_REQUEST: i32 = -32600;
pub const METHOD_NOT_FOUND: i32 = -32601;
pub const INVALID_PARAMS: i32 = -32602;

/// A JSON-RPC error, used for requests that cannot reach a tool at all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl RpcError {
    pub fn invalid_params(message: impl Into<String>) -> Self {
        Self {
            code: INVALID_PARAMS,
            message: message.into(),
        }
    }
}

/// The text a tool returns, plus whether the text describes a failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolResult {
    pub text: String,
    pub is_error: bool,
}

impl ToolResult {
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            is_error: false,
        }
    }

    pub fn error(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            is_error: true,
        }
    }
}

pub fn success(id: &Value, result: &Value) -> Value {
    json!({"jsonrpc": JSONRPC_VERSION, "id": id, "result": result})
}

pub fn error(id: &Value, code: i32, message: &str) -> Value {
    json!({
        "jsonrpc": JSONRPC_VERSION,
        "id": id,
        "error": {"code": code, "message": message}
    })
}

/// Initialize result: echo a supported client version, otherwise offer ours.
pub fn initialize(params: &Value) -> Value {
    let requested = params.get("protocolVersion").and_then(Value::as_str);
    let version = requested
        .filter(|version| SUPPORTED_PROTOCOL_VERSIONS.contains(version))
        .unwrap_or(LATEST_PROTOCOL_VERSION);
    json!({
        "protocolVersion": version,
        "capabilities": {"tools": {}},
        "serverInfo": {
            "name": SERVER_NAME,
            "version": env!("CARGO_PKG_VERSION")
        },
        "instructions": "Erst is a local, searchable memory of the text on this Mac's screen. Tools return text only; images are never available."
    })
}

/// The tool catalog advertised to clients.
pub fn tools() -> Value {
    json!({
        "tools": [
            {
                "name": "search_screen_history",
                "description": "Search text that appeared on this Mac's screen. Returns moments with local time, app, window title, URL, matched lines, and frame_id. Text only.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Words to search for. Supports app:Safari, today, yesterday, since:2026-10-01, until:2026-10-20, and \"exact phrases\"."
                        },
                        "limit": {
                            "type": "integer",
                            "minimum": MIN_SEARCH_LIMIT,
                            "maximum": MAX_SEARCH_LIMIT,
                            "default": DEFAULT_SEARCH_LIMIT,
                            "description": "Maximum number of moments to return."
                        }
                    },
                    "required": ["query"],
                    "additionalProperties": false
                }
            },
            {
                "name": "get_moment",
                "description": "Read every text line of one moment in reading order (top to bottom, left to right), with app, window title, URL, and local time. Text only.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "frame_id": {
                            "type": "integer",
                            "description": "The frame_id of a moment from search_screen_history."
                        }
                    },
                    "required": ["frame_id"],
                    "additionalProperties": false
                }
            },
            {
                "name": "activity_summary",
                "description": "Summarize screen time for one local day: total, per category, top apps, and top websites. Text only.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "day": {
                            "type": "string",
                            "pattern": "^\\d{4}-\\d{2}-\\d{2}$",
                            "description": "Local day in YYYY-MM-DD. Defaults to today."
                        }
                    },
                    "additionalProperties": false
                }
            }
        ]
    })
}

/// A `tools/call` result envelope.
pub fn tool_result(result: &ToolResult) -> Value {
    json!({
        "content": [{"type": "text", "text": result.text}],
        "isError": result.is_error
    })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use serde_json::{Value, json};

    use super::{LATEST_PROTOCOL_VERSION, ToolResult, initialize, tools};

    #[test]
    fn initialize_echoes_a_supported_client_version() {
        let result = initialize(&json!({"protocolVersion": "2025-06-18"}));
        assert_eq!(result["protocolVersion"], "2025-06-18");
        assert_eq!(result["serverInfo"]["name"], "erst");
        assert_eq!(result["serverInfo"]["version"], env!("CARGO_PKG_VERSION"));
        assert!(result["capabilities"]["tools"].is_object());
    }

    #[test]
    fn initialize_falls_back_for_an_unknown_version() {
        let result = initialize(&json!({"protocolVersion": "1999-01-01"}));
        assert_eq!(result["protocolVersion"], LATEST_PROTOCOL_VERSION);
    }

    #[test]
    fn initialize_works_without_params() {
        let result = initialize(&Value::Null);
        assert_eq!(result["protocolVersion"], LATEST_PROTOCOL_VERSION);
    }

    #[test]
    fn tools_list_contains_the_three_text_tools() {
        let listed = tools();
        let tools = listed["tools"].as_array().unwrap();
        let names: Vec<&str> = tools
            .iter()
            .filter_map(|tool| tool["name"].as_str())
            .collect();
        assert_eq!(
            names,
            vec!["search_screen_history", "get_moment", "activity_summary"]
        );
        for tool in tools {
            assert_eq!(tool["inputSchema"]["type"], "object");
            assert!(tool["description"].as_str().unwrap().contains("Text only"));
        }
    }

    #[test]
    fn tool_results_are_text_content() {
        let ok = super::tool_result(&ToolResult::text("hello"));
        assert_eq!(ok["content"][0]["type"], "text");
        assert_eq!(ok["content"][0]["text"], "hello");
        assert_eq!(ok["isError"], false);
        let failed = super::tool_result(&ToolResult::error("broken"));
        assert_eq!(failed["isError"], true);
    }
}
