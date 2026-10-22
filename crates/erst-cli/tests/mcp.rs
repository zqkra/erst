//! End to end tests of `erst mcp` over its stdio transport.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

use common::{APP_NAME, erst, fixture, fixture_with, stderr, stdout};
use serde_json::{Value, json};

struct McpClient {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next_id: i64,
}

impl McpClient {
    fn start(dir: &Path) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_erst"))
            .arg("--data-dir")
            .arg(dir)
            .arg("mcp")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn erst mcp");
        let stdin = child.stdin.take().expect("stdin");
        let stdout = BufReader::new(child.stdout.take().expect("stdout"));
        Self {
            child,
            stdin,
            stdout,
            next_id: 1,
        }
    }

    fn send(&mut self, message: &Value) {
        writeln!(self.stdin, "{message}").expect("write message");
        self.stdin.flush().expect("flush message");
    }

    fn read_message(&mut self) -> Value {
        let mut line = String::new();
        let read = self.stdout.read_line(&mut line).expect("read message");
        assert!(read > 0, "server closed stdout");
        serde_json::from_str(&line).expect("response is JSON")
    }

    fn request(&mut self, method: &str, params: &Value) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        self.send(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        }));
        let response = self.read_message();
        assert_eq!(response["id"], id, "{response}");
        response
    }

    fn notify(&mut self, method: &str) {
        self.send(&json!({"jsonrpc": "2.0", "method": method}));
    }

    fn call(&mut self, name: &str, arguments: &Value) -> Value {
        self.request("tools/call", &json!({"name": name, "arguments": arguments}))
    }
}

impl Drop for McpClient {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn text_of(response: &Value) -> String {
    response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("no text content in {response}"))
        .to_owned()
}

fn is_tool_error(response: &Value) -> bool {
    response["result"]["isError"].as_bool().unwrap_or(false)
}

#[test]
fn mcp_initializes_lists_tools_and_answers_each_tool() {
    let fixture = fixture();
    let mut client = McpClient::start(fixture.dir.path());

    let init = client.request(
        "initialize",
        &json!({
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "test", "version": "0"}
        }),
    );
    assert!(init.get("error").is_none(), "{init}");
    assert_eq!(init["result"]["serverInfo"]["name"], "erst");
    assert_eq!(init["result"]["protocolVersion"], "2025-06-18");
    assert_eq!(init["result"]["capabilities"]["tools"], json!({}));

    client.notify("notifications/initialized");
    let ping = client.request("ping", &json!({}));
    assert!(ping.get("error").is_none(), "{ping}");
    assert!(ping["result"].is_object());

    let listed = client.request("tools/list", &json!({}));
    let names: Vec<&str> = listed["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|tool| tool["name"].as_str())
        .collect();
    assert_eq!(
        names,
        vec!["search_screen_history", "get_moment", "activity_summary"]
    );
    for tool in listed["result"]["tools"].as_array().unwrap() {
        assert_eq!(tool["inputSchema"]["type"], "object");
    }

    let search = client.call("search_screen_history", &json!({"query": "zebra"}));
    assert!(!is_tool_error(&search), "{search}");
    let search_text = text_of(&search);
    assert!(search_text.contains("zebra notes"), "{search_text}");
    assert!(search_text.contains(APP_NAME), "{search_text}");
    assert_eq!(search_text.matches("frame_id:").count(), 2, "{search_text}");

    let limited = client.call(
        "search_screen_history",
        &json!({"query": "zebra", "limit": 1}),
    );
    assert_eq!(text_of(&limited).matches("frame_id:").count(), 1);

    let moment = client.call(
        "get_moment",
        &json!({"frame_id": fixture.seed.ordered_frame_id}),
    );
    assert!(!is_tool_error(&moment), "{moment}");
    let moment_text = text_of(&moment);
    let top = moment_text.find("top text").expect("top line");
    let bottom = moment_text.find("bottom text").expect("bottom line");
    assert!(top < bottom, "{moment_text}");
    assert!(moment_text.contains(APP_NAME));
    assert!(moment_text.contains("frame_id:"));

    let missing = client.call("get_moment", &json!({"frame_id": 999_999}));
    assert!(is_tool_error(&missing));
    assert!(text_of(&missing).contains("No moment with frame_id"));

    let activity = client.call(
        "activity_summary",
        &json!({"day": fixture.seed.activity_day}),
    );
    assert!(!is_tool_error(&activity), "{activity}");
    let activity_text = text_of(&activity);
    assert!(activity_text.contains("Building"), "{activity_text}");
    assert!(activity_text.contains("Xcode"), "{activity_text}");

    let bad_day = client.call("activity_summary", &json!({"day": "2026-02-30"}));
    assert!(is_tool_error(&bad_day));
    assert!(text_of(&bad_day).contains("Invalid day"));

    let unknown_tool = client.call("open_image", &json!({}));
    assert_eq!(unknown_tool["error"]["code"], -32602);

    let unknown_method = client.request("resources/list", &json!({}));
    assert_eq!(unknown_method["error"]["code"], -32601);
}

#[test]
fn mcp_reports_a_parse_error_without_crashing() {
    let fixture = fixture();
    let mut client = McpClient::start(fixture.dir.path());
    client.request("initialize", &json!({}));

    writeln!(client.stdin, "this is not json").expect("write broken line");
    client.stdin.flush().expect("flush broken line");
    let response = client.read_message();
    assert_eq!(response["error"]["code"], -32700);
    assert!(response["id"].is_null());

    let ping = client.request("ping", &json!({}));
    assert!(ping.get("error").is_none(), "{ping}");
}

#[test]
fn mcp_honors_the_agent_history_window() {
    let fixture = fixture_with(Some(r#"{"agent_history_days": 2}"#), true);
    let old_frame_id = fixture.seed.old_frame_id.expect("old frame");
    let mut client = McpClient::start(fixture.dir.path());
    client.request("initialize", &json!({}));

    let search = client.call("search_screen_history", &json!({"query": "zebra"}));
    assert!(!is_tool_error(&search), "{search}");
    let search_text = text_of(&search);
    assert!(search_text.contains("zebra notes"), "{search_text}");
    assert!(!search_text.contains("zebra archive"), "{search_text}");
    assert!(
        search_text.contains("Limited to the last 2 days"),
        "{search_text}"
    );

    let moment = client.call("get_moment", &json!({"frame_id": old_frame_id}));
    assert!(is_tool_error(&moment));
    assert!(text_of(&moment).contains("older than the agent history window"));

    let old_day = fixture.seed.old_day.clone().expect("old day");
    let activity = client.call("activity_summary", &json!({"day": old_day}));
    assert!(is_tool_error(&activity));
    assert!(text_of(&activity).contains("older than the agent history window"));

    // The CLI honors the same window, because an agent can read through it too.
    let cli = erst(&fixture, &["search", "zebra", "--json"]);
    assert!(cli.status.success(), "{}", stderr(&cli));
    assert!(!stdout(&cli).contains("zebra archive"), "{}", stdout(&cli));
    assert!(
        stderr(&cli).contains("Limited to the last 2 days"),
        "{}",
        stderr(&cli)
    );
    let old_moment = erst(&fixture, &["moment", &old_frame_id.to_string()]);
    assert!(!old_moment.status.success());
    assert!(stderr(&old_moment).contains("older than the agent history window"));
    let old_activity = erst(&fixture, &["activity", "--day", &old_day]);
    assert!(!old_activity.status.success());
    assert!(stderr(&old_activity).contains("older than the agent history window"));
}

#[test]
fn mcp_without_the_setting_returns_all_history() {
    assert_mcp_returns_all_history(None);
}

#[test]
fn mcp_with_a_null_agent_history_setting_returns_all_history() {
    assert_mcp_returns_all_history(Some(r#"{"agent_history_days": null}"#));
}

fn assert_mcp_returns_all_history(settings: Option<&str>) {
    let fixture = fixture_with(settings, true);
    let mut client = McpClient::start(fixture.dir.path());
    client.request("initialize", &json!({}));

    let search = client.call("search_screen_history", &json!({"query": "zebra"}));
    assert!(!is_tool_error(&search), "{search}");
    let text = text_of(&search);
    assert!(text.contains("zebra archive"), "{text}");
    assert!(!text.contains("Limited to the last"), "{text}");
    assert_eq!(text.matches("frame_id:").count(), 3, "{text}");
}

#[test]
fn mcp_blocks_agent_reads_when_the_settings_document_is_unreadable() {
    let fixture = fixture_with(Some("not json"), true);
    let old_frame_id = fixture.seed.old_frame_id.expect("old frame");
    let mut client = McpClient::start(fixture.dir.path());
    client.request("initialize", &json!({}));

    let search = client.call("search_screen_history", &json!({"query": "zebra"}));
    assert!(is_tool_error(&search), "{search}");
    let search_text = text_of(&search);
    assert!(
        search_text.contains("agent reads are blocked"),
        "{search_text}"
    );
    assert!(!search_text.contains("zebra notes"), "{search_text}");

    let moment = client.call("get_moment", &json!({"frame_id": old_frame_id}));
    assert!(is_tool_error(&moment), "{moment}");
    assert!(text_of(&moment).contains("agent reads are blocked"));

    let activity = client.call("activity_summary", &json!({}));
    assert!(is_tool_error(&activity), "{activity}");
    assert!(text_of(&activity).contains("agent reads are blocked"));
}

#[test]
fn mcp_answers_a_batch_with_one_invalid_request_and_a_null_id() {
    let fixture = fixture();
    let mut client = McpClient::start(fixture.dir.path());
    client.request("initialize", &json!({}));

    client.send(&json!([{"jsonrpc": "2.0", "id": 7, "method": "ping"}]));
    let batch = client.read_message();
    assert_eq!(batch["error"]["code"], -32600, "{batch}");
    assert!(batch["id"].is_null(), "{batch}");

    client.send(&json!(42));
    let scalar = client.read_message();
    assert_eq!(scalar["error"]["code"], -32600, "{scalar}");
    assert!(scalar["id"].is_null(), "{scalar}");

    let ping = client.request("ping", &json!({}));
    assert!(ping.get("error").is_none(), "{ping}");
}
