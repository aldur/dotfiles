//! The reader for Claude Code. Its files are in
//! `~/.claude/projects/<directory>/<uuid>.jsonl`.
//!
//! A record has the form `{type: user|assistant, message: {role, content}}`.
//! The content is a text or a list of blocks. The thinking, the tool calls and
//! the tool results are blocks. Thus a reader that uses only the `text` field
//! loses most of a session.

use serde_json::Value;

use crate::model::{flatten, Session, Turn};
use crate::style;

use super::{clock, parse_timestamp};

/// The text of one content block, for all the types of block.
fn block_text(block: &Value) -> String {
    match block.get("type").and_then(Value::as_str) {
        Some("text") => block.get("text").and_then(Value::as_str).unwrap_or("").to_string(),
        Some("thinking") => block
            .get("thinking")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        Some("tool_use") => {
            let name = block.get("name").and_then(Value::as_str).unwrap_or("?");
            let input = block.get("input").map(|i| i.to_string()).unwrap_or_default();
            format!("{name} {input}")
        }
        Some("tool_result") => match block.get("content") {
            Some(Value::String(text)) => text.clone(),
            Some(Value::Array(parts)) => parts
                .iter()
                .map(|p| p.get("text").and_then(Value::as_str).unwrap_or(""))
                .collect::<Vec<_>>()
                .join(" "),
            _ => String::new(),
        },
        _ => String::new(),
    }
}

fn is_tool_block(block: &Value) -> bool {
    matches!(
        block.get("type").and_then(Value::as_str),
        Some("tool_use") | Some("tool_result")
    )
}

fn message_text(message: &Value) -> String {
    message_text_filtered(message, false)
}

fn message_text_filtered(message: &Value, no_tools: bool) -> String {
    match message.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => {
            let parts: Vec<String> = blocks
                .iter()
                .filter(|b| !(no_tools && is_tool_block(b)))
                .map(block_text)
                .filter(|p| !p.is_empty())
                .collect();
            parts.join(" ")
        }
        _ => String::new(),
    }
}

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
    let mut corpus = String::new();
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
        let text = message_text(message);
        if first_user.is_empty()
            && record.get("type").and_then(Value::as_str) == Some("user")
            && matches!(message.get("content"), Some(Value::String(_)))
        {
            first_user = flatten(&text);
        }
        corpus.push_str(&text);
        corpus.push(' ');
    }

    Session {
        path: path.to_string(),
        id: file_stem(path),
        agent: "claude",
        cwd,
        last_activity: if last_activity > 0 { last_activity } else { mtime },
        when: String::new(),
        model,
        // The title is also free text. Thus remove the control sequences, as
        // for all the other text in a row.
        title: if title.is_empty() { first_user } else { flatten(&title) },
        corpus: flatten(&corpus),
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
        let text = flatten(&message_text_filtered(message, no_tools));
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
            time: clock(record.get("timestamp").and_then(Value::as_str).unwrap_or("")),
            text,
        });
    }
    turns
}

/// One turn as the role and the body. The caller makes the heading, because
/// the conversation view uses markdown for a file and a coloured bar for a
/// terminal.
pub fn render(record: &Value) -> (String, String) {
    let Some(message) = record.get("message") else {
        return (String::new(), String::new());
    };
    let role = record.get("type").and_then(Value::as_str).unwrap_or("?");
    let body = match message.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => blocks
            .iter()
            .map(|block| match block.get("type").and_then(Value::as_str) {
                Some("thinking") => format!("{}\n{}", style::heading("thinking", ""), style::thinking(&block_text(block))),
                Some("tool_use") => format!(
                    "{}\n{}",
                    style::heading(&format!("tool: {}", block.get("name").and_then(Value::as_str).unwrap_or("?")), ""),
                    style::dim(
                        &block
                            .get("input")
                            .map(|i| serde_json::to_string_pretty(i).unwrap_or_default())
                            .unwrap_or_default()
                    )
                ),
                Some("tool_result") => format!("{}\n{}", style::heading("tool result", ""), style::dim(&block_text(block))),
                _ => block_text(block),
            })
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
            .join("\n\n"),
        _ => String::new(),
    };
    (role.to_string(), body)
}
