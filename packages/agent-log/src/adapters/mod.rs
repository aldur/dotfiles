//! The detection of the format and the reader for each agent.
//!
//! The detection uses the content of the records and not the path. Thus a
//! transcript that a person copies to another directory still works.

use serde_json::Value;

use crate::model::{Session, Turn};

pub mod claude;
pub mod codex;
pub mod pi;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Agent {
    Claude,
    Pi,
    Codex,
}

impl Agent {
    pub fn parse(name: &str) -> Option<Agent> {
        match name {
            "claude" => Some(Agent::Claude),
            "pi" => Some(Agent::Pi),
            "codex" => Some(Agent::Codex),
            _ => None,
        }
    }
}

/// The agent that wrote these records. Each format identifies itself in its
/// records. Thus examine only the first records, and do not use more time on a
/// large transcript.
pub fn detect(records: &[Value]) -> Option<Agent> {
    for record in records.iter().take(50) {
        // Codex puts each item in a payload and gives a type to the record.
        if record.get("payload").is_some() {
            if let Some(kind) = record.get("type").and_then(Value::as_str) {
                if matches!(
                    kind,
                    "session_meta" | "response_item" | "turn_context" | "event_msg" | "compacted"
                ) {
                    return Some(Agent::Codex);
                }
            }
        }
        match record.get("type").and_then(Value::as_str) {
            // pi puts the message in a `message` field and starts with a
            // session record. Claude puts the role in the record.
            Some("session") => return Some(Agent::Pi),
            Some("message") if record.get("message").is_some() => return Some(Agent::Pi),
            Some("user") | Some("assistant") | Some("ai-title") | Some("summary") => {
                return Some(Agent::Claude)
            }
            _ => {}
        }
    }
    None
}

/// Each adapter does two operations. It summarizes a file for the picker, and
/// it divides the file into turns.
pub fn summarize(agent: Agent, path: &str, records: &[Value], mtime: i64) -> Session {
    match agent {
        Agent::Claude => claude::summarize(path, records, mtime),
        Agent::Pi => pi::summarize(path, records, mtime),
        Agent::Codex => codex::summarize(path, records, mtime),
    }
}

/// `no_tools` removes the tool blocks and not the full turns. An assistant
/// turn frequently contains the thinking, a tool call and the answer. If you
/// remove the full turn, you also remove the answer.
pub fn turns(agent: Agent, records: &[Value], no_tools: bool) -> Vec<Turn> {
    match agent {
        Agent::Claude => claude::turns(records, no_tools),
        Agent::Pi => pi::turns(records, no_tools),
        Agent::Codex => codex::turns(records, no_tools),
    }
}

/// Make a time in seconds from an RFC 3339 text such as
/// `2026-08-10T14:38:31.021Z`.
///
/// All the formats use RFC 3339 in UTC, and this is the only calculation that
/// the program does. Thus a date library is not necessary.
pub fn parse_timestamp(stamp: &str) -> Option<i64> {
    let bytes = stamp.as_bytes();
    if bytes.len() < 19 {
        return None;
    }
    let num = |from: usize, to: usize| -> Option<i64> { stamp.get(from..to)?.parse().ok() };
    let (year, month, day) = (num(0, 4)?, num(5, 7)?, num(8, 10)?);
    let (hour, min, sec) = (num(11, 13)?, num(14, 16)?, num(17, 19)?);

    // The days from the epoch, with the algorithm of Howard Hinnant.
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146_097 + day_of_era - 719_468;

    Some(days * 86_400 + hour * 3_600 + min * 60 + sec)
}

/// The `HH:MM:SS` part of an RFC 3339 text, for the time column.
pub fn clock(stamp: &str) -> String {
    stamp.get(11..19).unwrap_or("").to_string()
}
