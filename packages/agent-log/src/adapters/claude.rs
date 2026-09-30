//! The reader for Claude Code. Its files are in
//! `~/.claude/projects/<directory>/<uuid>.jsonl`.
//!
//! A record has the form `{type: user|assistant, message: {role, content}}`.
//! The content is a text or a list of blocks. The thinking, the tool calls and
//! the tool results are blocks. Thus a reader that uses only the `text` field
//! loses most of a session.

use serde_json::Value;

use super::{clock, is_empty_thinking, is_tool_block, message_text, parse_timestamp};
use crate::model::{flatten, Session, Turn};

fn is_turn(record: &Value) -> bool {
    matches!(
        record.get("type").and_then(Value::as_str),
        Some("user") | Some("assistant")
    )
}

fn file_stem(path: &str) -> String {
    std::path::Path::new(path)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default()
}

pub fn summarize(path: &str, records: &[Value], mtime: i64) -> Session {
    let mut last_activity = 0;
    let mut title = String::new();
    let mut first_user = String::new();
    let mut model = String::new();
    let mut cwd = String::new();

    for record in records {
        if let Some(stamp) = record.get("timestamp").and_then(Value::as_str) {
            if let Some(secs) = parse_timestamp(stamp) {
                last_activity = last_activity.max(secs);
            }
        }
        if cwd.is_empty() {
            if let Some(dir) = record.get("cwd").and_then(Value::as_str) {
                cwd = dir.to_string();
            }
        }
        // A file can have more than one ai-title record. The last record
        // has the current title.
        if record.get("type").and_then(Value::as_str) == Some("ai-title") {
            if let Some(text) = record.get("aiTitle").and_then(Value::as_str) {
                title = text.to_string();
            }
        }
        if !is_turn(record) {
            continue;
        }
        let Some(message) = record.get("message") else {
            continue;
        };
        if model.is_empty() {
            if let Some(name) = message.get("model").and_then(Value::as_str) {
                model = name.to_string();
            }
        }
        if first_user.is_empty()
            && record.get("type").and_then(Value::as_str) == Some("user")
            && matches!(message.get("content"), Some(Value::String(_)))
        {
            first_user = flatten(&message_text(message, false));
        }
    }

    Session {
        path: path.to_string(),
        id: file_stem(path),
        agent: "claude",
        cwd,
        last_activity: if last_activity > 0 {
            last_activity
        } else {
            mtime
        },
        model,
        // The title is also free text. Thus remove the control sequences, as
        // for all the other text in a row.
        title: if title.is_empty() {
            first_user
        } else {
            flatten(&title)
        },
    }
}

pub fn turns(records: &[Value], no_tools: bool) -> Vec<Turn> {
    let mut turns = Vec::new();
    for (index, record) in records.iter().enumerate() {
        if !is_turn(record) {
            continue;
        }
        let Some(message) = record.get("message") else {
            continue;
        };
        let text = flatten(&message_text(message, no_tools));
        if text.is_empty() {
            continue;
        }
        // The types of the blocks give more data than the type of the
        // record. A `user` record with tool_result blocks contains the output
        // of a tool and not the text of a person.
        let kind = match message.get("content") {
            Some(Value::Array(blocks)) => {
                let mut kinds: Vec<&str> = blocks
                    .iter()
                    .filter(|b| !(no_tools && is_tool_block(b)))
                    .filter(|b| !is_empty_thinking(b))
                    .filter_map(|b| b.get("type").and_then(Value::as_str))
                    .collect();
                kinds.dedup();
                kinds.join(",")
            }
            _ => record
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .to_string(),
        };
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
