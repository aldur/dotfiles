//! The reader for a llama-wiretap transcript. The file is the value of
//! `--log`.
//!
//! This is not the store of an agent. It is the only record that has the
//! system prompt, the tool definitions and the text that the chat template
//! makes. Thus it belongs in the same picker as the sessions.
//!
//! One exchange has two records with the same `id`. The state is `open` when
//! the proxy sends the request, and `done` when the response is complete. An
//! `open` record without a `done` record shows an incomplete exchange.

use serde_json::Value;

use crate::model::{flatten, truncate, Session, Turn};
use crate::style;

use super::{clock, parse_timestamp};

fn message_text(message: &Value) -> String {
    match message.get("content") {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => blocks
            .iter()
            .map(|b| b.get("text").and_then(Value::as_str).unwrap_or(""))
            .filter(|t| !t.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        _ => String::new(),
    }
}

fn is_completion(record: &Value) -> bool {
    record
        .get("path")
        .and_then(Value::as_str)
        .is_some_and(|p| p.contains("/chat/completions"))
}

fn request_text(record: &Value) -> String {
    let Some(messages) = record.pointer("/request/messages").and_then(Value::as_array) else {
        return String::new();
    };
    messages.iter().map(message_text).collect::<Vec<_>>().join(" ")
}

/// The last message of the user. This is the text that a person wrote. The
/// system prompt starts each request, thus it makes all the rows the same.
fn last_user(record: &Value) -> String {
    record
        .pointer("/request/messages")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|m| m.get("role").and_then(Value::as_str) == Some("user"))
        .map(message_text)
        .next_back()
        .unwrap_or_default()
}

fn file_stem(path: &str) -> String {
    std::path::Path::new(path)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default()
}

pub fn summarize(path: &str, records: &[Value], mtime: i64) -> Session {
    let mut last_activity = 0;
    let mut model = String::new();
    let mut first_user = String::new();
    let mut corpus = String::new();

    for record in records {
        if let Some(stamp) = record.get("at").and_then(Value::as_str) {
            if let Some(secs) = parse_timestamp(stamp) {
                last_activity = last_activity.max(secs);
            }
        }
        if model.is_empty() {
            if let Some(name) = record.pointer("/request/model").and_then(Value::as_str) {
                model = name.to_string();
            }
        }
        if record.get("state").and_then(Value::as_str) != Some("done") || !is_completion(record) {
            continue;
        }
        if first_user.is_empty() {
            first_user = flatten(&last_user(record));
        }
        corpus.push_str(&request_text(record));
        corpus.push(' ');
    }

    Session {
        path: path.to_string(),
        id: file_stem(path),
        agent: "wire",
        cwd: String::new(),
        last_activity: if last_activity > 0 { last_activity } else { mtime },
        when: String::new(),
        model,
        title: first_user,
        corpus: flatten(&corpus),
    }
}

pub fn turns(records: &[Value]) -> Vec<Turn> {
    // Make one row for each exchange. A `done` record replaces the `open`
    // record with the same id. Thus a complete exchange does not show the
    // state of an incomplete one.
    let mut order: Vec<String> = Vec::new();
    let mut rows: Vec<(String, Turn)> = Vec::new();

    for record in records.iter().filter(|r| is_completion(r)) {
        let Some(state) = record.get("state").and_then(Value::as_str) else {
            continue;
        };
        if state != "open" && state != "done" {
            continue;
        }
        let id = match record.get("id") {
            Some(Value::Number(n)) => n.to_string(),
            Some(Value::String(s)) => s.clone(),
            _ => continue,
        };
        let kind = if state == "done" {
            let status = record.get("status").and_then(Value::as_i64).unwrap_or(0);
            format!("done {status}")
        } else {
            "in flight".to_string()
        };
        let turn = Turn {
            key: id.clone(),
            kind,
            time: clock(record.get("at").and_then(Value::as_str).unwrap_or("")),
            label: truncate(&flatten(&last_user(record)), 200),
            text: flatten(&request_text(record)),
        };
        match rows.iter_mut().find(|(existing, _)| *existing == id) {
            // Only a `done` record can replace a row.
            Some(slot) if state == "done" => slot.1 = turn,
            Some(_) => {}
            None => {
                order.push(id.clone());
                rows.push((id, turn));
            }
        }
    }

    let _ = order;
    rows.into_iter().map(|(_, turn)| turn).collect()
}

/// Collect one part of the response. llama.cpp sends the reasoning in
/// `reasoning_content` fields and the answer in `content` fields.
fn deltas(response: Option<&Value>, field: &str) -> String {
    let Some(Value::String(body)) = response else {
        return String::new();
    };
    body.lines()
        .filter_map(|line| line.strip_prefix("data: "))
        .filter_map(|json| serde_json::from_str::<Value>(json).ok())
        .filter_map(|event| {
            event
                .pointer(&format!("/choices/0/delta/{field}"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .collect()
}

/// One exchange as the type and the body. The key is the id of the exchange.
///
/// The other formats have one record for each turn. Here the request contains
/// a full conversation, and the response is a sequence of parts. Thus this
/// function makes the two sides again.
pub fn render(records: &[Value], key: &str) -> (String, String) {
    let mut chosen: Option<&Value> = None;
    for record in records.iter().filter(|r| is_completion(r)) {
        let id = match record.get("id") {
            Some(Value::Number(n)) => n.to_string(),
            Some(Value::String(s)) => s.clone(),
            _ => continue,
        };
        if id != key {
            continue;
        }
        // A `done` record has priority over an `open` record.
        if record.get("state").and_then(Value::as_str) == Some("done") || chosen.is_none() {
            chosen = Some(record);
        }
    }
    let Some(record) = chosen else {
        return (String::new(), format!("no exchange {key}"));
    };

    let done = record.get("state").and_then(Value::as_str) == Some("done");
    let kind = if done {
        format!("done {}", record.get("status").and_then(Value::as_i64).unwrap_or(0))
    } else {
        "in flight".to_string()
    };

    let mut body = String::new();
    let mut meta: Vec<String> = Vec::new();
    if let Some(model) = record.pointer("/request/model").and_then(Value::as_str) {
        meta.push(model.to_string());
    }
    if let Some(tokens) = record.get("promptTokens").and_then(Value::as_i64) {
        meta.push(format!("{tokens} prompt tokens"));
    }
    if !meta.is_empty() {
        body.push_str(&format!("{}\n\n", style::dim(&meta.join(" · "))));
    }

    for message in record
        .pointer("/request/messages")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let role = message.get("role").and_then(Value::as_str).unwrap_or("?");
        let text = message_text(message);
        if text.is_empty() {
            continue;
        }
        body.push_str(&format!("{}\n{}\n\n", style::heading(role, ""), text));
    }

    if done {
        let thinking = deltas(record.get("response"), "reasoning_content");
        if !thinking.is_empty() {
            body.push_str(&format!(
                "{}\n{}\n\n",
                style::heading("thinking", ""),
                style::thinking(&thinking)
            ));
        }
        let answer = deltas(record.get("response"), "content");
        body.push_str(&format!(
            "{}\n{}\n",
            style::heading("answer", ""),
            if answer.is_empty() { style::dim("(empty)") } else { answer }
        ));
    } else {
        body.push_str(&style::dim(
            "No response recorded — the model was still generating, or the request died.",
        ));
        body.push('\n');
    }

    (kind, body)
}
