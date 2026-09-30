//! The reader for Codex. Its files are in
//! `~/.codex/sessions/<year>/<month>/<day>/rollout-<time>-<uuid>.jsonl`.
//!
//! Optional fields and unknown record types are tolerated so logs from
//! different Codex versions can be read together.
//!
//! Expected envelope:
//!   {"timestamp":…, "type":"session_meta",   "payload":{"id":…,"cwd":…,"instructions":…}}
//!   {"timestamp":…, "type":"turn_context",   "payload":{"cwd":…,"model":…}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"message","role":…,"content":[…]}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"reasoning","summary":[…]}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"function_call","name":…,"arguments":…}}
//!   {"timestamp":…, "type":"response_item",  "payload":{"type":"function_call_output","output":…}}

use serde_json::Value;

use crate::model::{flatten, Block, Session, Turn};

use super::{clock, content_text, message_blocks, parse_timestamp};

/// A display title, not a filter on the transcript. Codex injects setup as
/// user-role text, sometimes in the same content array as the real request.
/// Inspect blocks separately so setup cannot swallow the following request.
pub fn user_title(content: &Value) -> String {
    match content {
        Value::String(text) => flatten(request_text(text)),
        Value::Array(parts) => parts
            .iter()
            .filter_map(|part| part.get("text").and_then(Value::as_str))
            .map(request_text)
            .map(flatten)
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        _ => String::new(),
    }
}

fn request_text(mut text: &str) -> &str {
    loop {
        text = text.trim();
        match crate::context::prefix(text) {
            Some(block) if crate::context::is_setup(block.tag) => text = block.rest,
            _ => {
                if text.starts_with("# Context from my IDE setup:") {
                    return text
                        .split_once("## My request for Codex:")
                        .map_or(text, |(_, request)| request.trim());
                }
                return text;
            }
        }
    }
}

pub fn session_title(first_user: String) -> String {
    if first_user.is_empty() {
        "(no user request yet)".to_owned()
    } else {
        first_user
    }
}

/// The type and the text of one payload. The result is None if the payload
/// has no text.
pub(super) fn payload_parts(payload: &Value) -> Option<(String, String)> {
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
        if first_user.is_empty()
            && payload.get("type").and_then(Value::as_str) == Some("message")
            && payload.get("role").and_then(Value::as_str) == Some("user")
        {
            first_user = user_title(&payload["content"]);
        }
    }

    Session {
        path: path.to_string(),
        id,
        agent: "codex",
        cwd,
        last_activity: if last_activity > 0 {
            last_activity
        } else {
            mtime
        },
        model,
        title: session_title(first_user),
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
            time: clock(
                record
                    .get("timestamp")
                    .and_then(Value::as_str)
                    .unwrap_or(""),
            ),
            text,
        });
    }
    turns
}

pub fn blocks(record: &Value) -> (String, Vec<Block>) {
    let Some(payload) = record.get("payload") else {
        return (String::new(), Vec::new());
    };
    if payload.get("type").and_then(Value::as_str) == Some("message") {
        return (
            payload
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .into(),
            message_blocks(&payload["content"], false),
        );
    }
    payload_parts(payload)
        .map(|(kind, text)| (kind, vec![Block::text(text)]))
        .unwrap_or_default()
}
