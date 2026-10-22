//! MCP server over stdio: newline-delimited JSON-RPC 2.0, one message per line.

mod protocol;
pub(crate) mod render;
mod tools;
mod window;

use std::io::{BufRead, Write};

use anyhow::Result;
use erst_store::Store;
use serde_json::Value;

use protocol::{INVALID_REQUEST, JSONRPC_VERSION, METHOD_NOT_FOUND, PARSE_ERROR};

/// Serves MCP on stdin and stdout until the client closes stdin.
///
/// Only protocol messages go to stdout. Everything diagnostic goes to stderr.
pub fn serve(store: &Store) -> Result<()> {
    eprintln!("erst mcp {} listening on stdio", env!("CARGO_PKG_VERSION"));
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    serve_on(stdin.lock(), stdout.lock(), store)
}

/// The transport loop: one request line in, at most one response line out.
fn serve_on(mut input: impl BufRead, mut output: impl Write, store: &Store) -> Result<()> {
    let mut line = String::new();
    loop {
        line.clear();
        if input.read_line(&mut line)? == 0 {
            return Ok(());
        }
        let message = line.trim();
        if message.is_empty() {
            continue;
        }
        if let Some(response) = handle(store, message, erst_core::now_ms()) {
            serde_json::to_writer(&mut output, &response)?;
            output.write_all(b"\n")?;
            output.flush()?;
        }
    }
}

/// Answers one line, or nothing when it is a notification.
///
/// A JSON-RPC batch (a top-level array) and any other message that is not an
/// object get one Invalid Request error with a null id. The MCP specification
/// revision 2025-06-18 removed batching, and the JSON-RPC spec requires the
/// error for a request it cannot read.
fn handle(store: &Store, message: &str, now_ms: i64) -> Option<Value> {
    let Ok(value) = serde_json::from_str::<Value>(message) else {
        return Some(protocol::error(
            &Value::Null,
            PARSE_ERROR,
            "parse error: expected one JSON-RPC message per line",
        ));
    };
    if !value.is_object() {
        return Some(protocol::error(
            &Value::Null,
            INVALID_REQUEST,
            "invalid request: send one JSON-RPC object per line; batches are not supported",
        ));
    }
    let id = match value.get("id") {
        Some(id) if !id.is_null() => Some(id.clone()),
        _ => None,
    };
    if value.get("jsonrpc").and_then(Value::as_str) != Some(JSONRPC_VERSION) {
        return id.map(|id| {
            protocol::error(
                &id,
                INVALID_REQUEST,
                "invalid request: jsonrpc must be \"2.0\"",
            )
        });
    }
    let Some(method) = value.get("method").and_then(Value::as_str) else {
        return id
            .map(|id| protocol::error(&id, INVALID_REQUEST, "invalid request: missing method"));
    };
    let id = id?;
    let params = value.get("params").cloned().unwrap_or(Value::Null);
    let response = match method {
        "initialize" => protocol::success(&id, &protocol::initialize(&params)),
        "ping" => protocol::success(&id, &Value::Object(serde_json::Map::new())),
        "tools/list" => protocol::success(&id, &protocol::tools()),
        "tools/call" => match tools::call(store, &params, now_ms) {
            Ok(result) => protocol::success(&id, &protocol::tool_result(&result)),
            Err(error) => protocol::error(&id, error.code, &error.message),
        },
        other => protocol::error(&id, METHOD_NOT_FOUND, &format!("method not found: {other}")),
    };
    Some(response)
}
