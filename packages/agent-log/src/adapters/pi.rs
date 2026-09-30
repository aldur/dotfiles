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

use super::{clock, message_text, parse_timestamp};
use crate::model::{flatten, Session, Turn};

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
                let provider = record
                    .get("provider")
                    .and_then(Value::as_str)
                    .unwrap_or("?");
                let id = record.get("modelId").and_then(Value::as_str).unwrap_or("?");
                model = format!("{provider}/{id}");
            }
            Some("message") => {
                let Some(message) = record.get("message") else {
                    continue;
                };
                if first_user.is_empty()
                    && message.get("role").and_then(Value::as_str) == Some("user")
                {
                    first_user = flatten(&message_text(message, false));
                }
            }
            _ => {}
        }
    }

    Session {
        path: path.to_string(),
        id,
        agent: "pi",
        cwd,
        last_activity: if last_activity > 0 {
            last_activity
        } else {
            mtime
        },
        model,
        title: first_user,
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
        let text = flatten(&message_text(message, no_tools));
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
