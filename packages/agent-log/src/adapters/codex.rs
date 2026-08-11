//! The reader for Codex. Its files are in
//! `~/.codex/sessions/<year>/<month>/<day>/rollout-<time>-<uuid>.jsonl`.
//!
//! WARNING: nobody examined this reader against a Codex session. The machine
//! had no such file. This code uses the published format only. Thus each field
//! is optional, the code ignores an unknown type, and no operation can stop
//! the program. If a Codex list is incorrect, examine this file first.
//!
//! Expected envelope:
//!   {"timestamp":…, "type":"session_meta",   "payload":{"id":…,"cwd":…,"instructions":…}}
//!   {"timestamp":…, "type":"turn_context",   "payload":{"cwd":…,"model":…}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"message","role":…,"content":[…]}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"reasoning","summary":[…]}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"function_call","name":…,"arguments":…}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"function_call_output","output":…}}

use serde_json::Value;

use crate::model::{flatten, truncate, Session, Turn};

use super::{clock, parse_timestamp};

/// A content block has the type `input_text`, `output_text` or `text`. Use
/// the text of each of them, and ignore the other types.
fn content_text(content: &Value) -> String {
    match content {
        Value::String(text) => text.clone(),
        Value::Array(parts) => parts
            .iter()
            .map(|part| part.get("text").and_then(Value::as_str).unwrap_or(""))
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        _ => String::new(),
    }
}

/// The type and the text of one payload. The result is None if the payload
/// has no text.
fn payload_parts(payload: &Value) -> Option<(String, String)> {
    match payload.get("type").and_then(Value::as_str)? {
        "message" => {
            let role = payload.get("role").and_then(Value::as_str).unwrap_or("?");
            let text = content_text(payload.get("content").unwrap_or(&Value::Null));
            (!text.is_empty()).then(|| (role.to_string(), text))
        }
        "reasoning" => {
            // The `summary` field has the short form of the reasoning. Some
            // versions also put the full text in the `content` field.
            let mut text = content_text(payload.get("summary").unwrap_or(&Value::Null));
            if text.is_empty() {
                text = content_text(payload.get("content").unwrap_or(&Value::Null));
            }
            (!text.is_empty()).then(|| ("thinking".to_string(), text))
        }
        "function_call" | "local_shell_call" | "custom_tool_call" => {
            let name = payload
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("tool")
                .to_string();
            let args = payload
                .get("arguments")
                .map(|a| match a {
                    Value::String(text) => text.clone(),
                    other => other.to_string(),
                })
                .unwrap_or_default();
            Some((format!("tool: {name}"), args))
        }
        "function_call_output" | "local_shell_call_output" | "custom_tool_call_output" => {
            let output = payload
                .get("output")
                .map(|o| match o {
                    Value::String(text) => text.clone(),
                    other => content_text(other),
                })
                .unwrap_or_default();
            Some(("tool result".to_string(), output))
        }
        _ => None,
    }
}

pub fn summarize(path: &str, records: &[Value], mtime: i64) -> Session {
    let mut last_activity = 0;
    let mut cwd = String::new();
    let mut model = String::new();
    let mut first_user = String::new();
    let mut corpus = String::new();
    let mut id = String::new();

    for record in records {
        if let Some(stamp) = record.get("timestamp").and_then(Value::as_str) {
            if let Some(secs) = parse_timestamp(stamp) {
                last_activity = last_activity.max(secs);
            }
        }
        let Some(payload) = record.get("payload") else {
            continue;
        };
        // A session_meta record and a turn_context record can each give the
        // working directory and the model. Use the first working directory and
        // the last model.
        if cwd.is_empty() {
            if let Some(dir) = payload.get("cwd").and_then(Value::as_str) {
                cwd = dir.to_string();
            }
        }
        if id.is_empty() {
            if let Some(session) = payload.get("id").and_then(Value::as_str) {
                id = session.to_string();
            }
        }
        if let Some(name) = payload.get("model").and_then(Value::as_str) {
            model = name.to_string();
        }
        if let Some((kind, text)) = payload_parts(payload) {
            if first_user.is_empty() && kind == "user" {
                first_user = flatten(&text);
            }
            corpus.push_str(&text);
            corpus.push(' ');
        }
    }

    Session {
        path: path.to_string(),
        id,
        agent: "codex",
        cwd,
        last_activity: if last_activity > 0 { last_activity } else { mtime },
        when: String::new(),
        model,
        title: first_user,
        corpus: flatten(&corpus),
    }
}

pub fn turns(records: &[Value], no_tools: bool) -> Vec<Turn> {
    let mut turns = Vec::new();
    for (index, record) in records.iter().enumerate() {
        let Some(payload) = record.get("payload") else {
            continue;
        };
        let Some((kind, text)) = payload_parts(payload) else {
            continue;
        };
        if no_tools && kind.starts_with("tool") {
            continue;
        }
        let text = flatten(&text);
        if text.is_empty() {
            continue;
        }
        turns.push(Turn {
            key: (index + 1).to_string(),
            kind,
            time: clock(record.get("timestamp").and_then(Value::as_str).unwrap_or("")),
            label: truncate(&text, 200),
            text,
        });
    }
    turns
}

/// One turn as the type and the body. Refer to claude::render.
pub fn render(record: &Value) -> (String, String) {
    let Some(payload) = record.get("payload") else {
        return (String::new(), String::new());
    };
    payload_parts(payload).unwrap_or_default()
}
