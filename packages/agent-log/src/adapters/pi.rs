//! The reader for pi. Its files are in
//! `~/.pi/agent/sessions/<directory>/<time>_<uuid>.jsonl`.
//!
//! A `session` record starts the file and gives the working directory. A
//! `model_change` record gives the provider and the model. Each turn is a
//! `message` record. Its content is a text or a list of blocks with the types
//! `text`, `thinking`, `toolCall` and `toolResult`.
//!
//! A session does not contain the system prompt or the tool definitions. pi
//! makes them again at each start. Only a llama-wiretap transcript has them.

use serde_json::Value;

use crate::model::{flatten, truncate, Session, Turn};
use crate::style;

use super::{clock, parse_timestamp};

fn block_text(block: &Value) -> String {
    match block.get("type").and_then(Value::as_str) {
        Some("text") => block.get("text").and_then(Value::as_str).unwrap_or("").to_string(),
        Some("thinking") => block
            .get("thinking")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        Some("toolCall") => {
            let name = block.get("name").and_then(Value::as_str).unwrap_or("?");
            let args = block
                .get("arguments")
                .map(|a| a.to_string())
                .unwrap_or_default();
            format!("{name} {args}")
        }
        Some("toolResult") => match block.get("content") {
            Some(Value::Array(parts)) => parts
                .iter()
                .map(|p| p.get("text").and_then(Value::as_str).unwrap_or(""))
                .collect::<Vec<_>>()
                .join(" "),
            Some(Value::String(text)) => text.clone(),
            _ => String::new(),
        },
        _ => String::new(),
    }
}

fn is_tool_block(block: &Value) -> bool {
    matches!(
        block.get("type").and_then(Value::as_str),
        Some("toolCall") | Some("toolResult")
    )
}

fn message_text(message: &Value) -> String {
    message_text_filtered(message, false)
}

fn message_text_filtered(message: &Value, no_tools: bool) -> String {
    match message.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => blocks
            .iter()
            .filter(|b| !(no_tools && is_tool_block(b)))
            .map(block_text)
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        _ => String::new(),
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
        match record.get("type").and_then(Value::as_str) {
            Some("session") => {
                if let Some(dir) = record.get("cwd").and_then(Value::as_str) {
                    cwd = dir.to_string();
                }
                if let Some(session) = record.get("id").and_then(Value::as_str) {
                    id = session.to_string();
                }
            }
            Some("model_change") => {
                let provider = record.get("provider").and_then(Value::as_str).unwrap_or("?");
                let id = record.get("modelId").and_then(Value::as_str).unwrap_or("?");
                model = format!("{provider}/{id}");
            }
            Some("message") => {
                let Some(message) = record.get("message") else {
                    continue;
                };
                let text = message_text(message);
                if first_user.is_empty()
                    && message.get("role").and_then(Value::as_str) == Some("user")
                    && !text.is_empty()
                {
                    first_user = flatten(&text);
                }
                corpus.push_str(&text);
                corpus.push(' ');
            }
            _ => {}
        }
    }

    Session {
        path: path.to_string(),
        id,
        agent: "pi",
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
        if record.get("type").and_then(Value::as_str) != Some("message") {
            continue;
        }
        let Some(message) = record.get("message") else {
            continue;
        };
        let text = flatten(&message_text_filtered(message, no_tools));
        if text.is_empty() {
            continue;
        }
        turns.push(Turn {
            key: (index + 1).to_string(),
            kind: message
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .to_string(),
            time: clock(record.get("timestamp").and_then(Value::as_str).unwrap_or("")),
            label: truncate(&text, 200),
            text,
        });
    }
    turns
}

/// One turn as the role and the body. Refer to claude::render.
pub fn render(record: &Value) -> (String, String) {
    let Some(message) = record.get("message") else {
        return (String::new(), String::new());
    };
    let role = message.get("role").and_then(Value::as_str).unwrap_or("?");
    let body = match message.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => blocks
            .iter()
            .map(|block| match block.get("type").and_then(Value::as_str) {
                Some("thinking") => format!("{}\n{}", style::heading("thinking", ""), style::thinking(&block_text(block))),
                Some("toolCall") => format!(
                    "{}\n{}",
                    style::heading(&format!("tool: {}", block.get("name").and_then(Value::as_str).unwrap_or("?")), ""),
                    style::dim(
                        &block
                            .get("arguments")
                            .map(|a| serde_json::to_string_pretty(a).unwrap_or_default())
                            .unwrap_or_default()
                    )
                ),
                Some("toolResult") => format!("{}\n{}", style::heading("tool result", ""), style::dim(&block_text(block))),
                _ => block_text(block),
            })
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
            .join("\n\n"),
        _ => String::new(),
    };
    (role.to_string(), body)
}
