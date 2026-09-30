//! A borrowing projection of JSONL metadata. Content is validated and skipped,
//! not decoded, copied, flattened or retained while listing conversations.

use std::borrow::Cow;
use std::path::Path;

use serde::de::Visitor;
use serde::{Deserialize, Deserializer};
use serde_json::Value;
use sonic_rs::LazyValue;
use std::fmt;

use crate::adapters::{self, Agent};
use crate::model::{flatten, Session};

/// Borrow ordinary JSON strings directly. Unlike a lazy JSON value, this
/// does not retain a fat JSON slice or parse each scalar a second time.
#[derive(Default)]
struct Text<'a>(Option<Cow<'a, str>>);

impl<'de: 'a, 'a> Deserialize<'de> for Text<'a> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct TextVisitor;
        impl<'de> Visitor<'de> for TextVisitor {
            type Value = Text<'de>;
            fn expecting(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
                out.write_str("a metadata string or null")
            }
            fn visit_borrowed_str<E>(self, value: &'de str) -> Result<Self::Value, E> {
                Ok(Text(Some(Cow::Borrowed(value))))
            }
            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E> {
                Ok(Text(Some(Cow::Owned(value.to_owned()))))
            }
            fn visit_string<E>(self, value: String) -> Result<Self::Value, E> {
                Ok(Text(Some(Cow::Owned(value))))
            }
            fn visit_unit<E>(self) -> Result<Self::Value, E> {
                Ok(Text(None))
            }
            fn visit_bool<E>(self, _: bool) -> Result<Self::Value, E> {
                Ok(Text(None))
            }
            fn visit_i64<E>(self, _: i64) -> Result<Self::Value, E> {
                Ok(Text(None))
            }
            fn visit_u64<E>(self, _: u64) -> Result<Self::Value, E> {
                Ok(Text(None))
            }
            fn visit_f64<E>(self, _: f64) -> Result<Self::Value, E> {
                Ok(Text(None))
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut seq: A,
            ) -> Result<Self::Value, A::Error> {
                while seq.next_element::<serde::de::IgnoredAny>()?.is_some() {}
                Ok(Text(None))
            }
            fn visit_map<A: serde::de::MapAccess<'de>>(
                self,
                mut map: A,
            ) -> Result<Self::Value, A::Error> {
                while map
                    .next_entry::<serde::de::IgnoredAny, serde::de::IgnoredAny>()?
                    .is_some()
                {}
                Ok(Text(None))
            }
        }
        deserializer.deserialize_any(TextVisitor)
    }
}

#[derive(Default, Deserialize)]
#[serde(default)]
pub struct Body<'a> {
    #[serde(borrow)]
    id: Text<'a>,
    cwd: Text<'a>,
    model: Text<'a>,
    #[serde(rename = "type")]
    kind: Text<'a>,
    role: Text<'a>,
    content: Option<LazyValue<'a>>,
}

#[derive(Default, Deserialize)]
#[serde(default)]
pub struct Record<'a> {
    #[serde(borrow, rename = "type")]
    kind: Text<'a>,
    timestamp: Text<'a>,
    cwd: Text<'a>,
    id: Text<'a>,
    #[serde(rename = "aiTitle")]
    title: Text<'a>,
    provider: Text<'a>,
    #[serde(rename = "modelId")]
    model_id: Text<'a>,
    message: Option<Body<'a>>,
    payload: Option<Body<'a>>,
}

fn text<'a>(raw: &'a Text<'_>) -> Option<&'a str> {
    raw.0.as_deref()
}

fn content_text<'a>(raw: &'a Option<LazyValue<'_>>) -> Option<Cow<'a, str>> {
    let raw = raw.as_ref()?.as_raw_str();
    serde_json::from_str::<&str>(raw)
        .map(Cow::Borrowed)
        .or_else(|_| serde_json::from_str::<String>(raw).map(Cow::Owned))
        .ok()
}

impl Record<'_> {
    pub fn agent(&self) -> Option<Agent> {
        let kind = text(&self.kind)?;
        if self.payload.is_some()
            && matches!(
                kind,
                "session_meta" | "response_item" | "turn_context" | "event_msg" | "compacted"
            )
        {
            return Some(Agent::Codex);
        }
        match kind {
            "session" => Some(Agent::Pi),
            "message" if self.message.is_some() => Some(Agent::Pi),
            "user" | "assistant" | "ai-title" | "summary" => Some(Agent::Claude),
            _ => None,
        }
    }
}

/// Inspect every record with bounded working buffers. A different first cwd
/// definitively excludes Claude/Codex files; pi can change cwd later.
pub fn summarize(
    path: &Path,
    mtime: i64,
    cwd: Option<&str>,
    scratch: &mut Vec<u8>,
    query: &crate::search::Query<'_>,
) -> Option<Session> {
    let mut initial: Vec<String> = Vec::new();
    let mut summary: Option<Summary> = None;
    let mut incompatible = false;
    let mut excluded = false;
    let mut matches = crate::search::Matches::new(query);
    crate::source::lines(path, scratch, |line| {
        let record = match sonic_rs::from_str::<Record<'_>>(line) {
            Ok(record) => record,
            Err(_) if serde_json::from_str::<serde::de::IgnoredAny>(line).is_ok() => {
                incompatible = true;
                return false;
            }
            Err(_) => return true,
        };
        if summary.is_none() {
            if let Some(agent) = record.agent() {
                let mut state = Summary::new(path, agent);
                for previous in &initial {
                    matches.record(agent, previous);
                    if state
                        .update(sonic_rs::from_str(previous).expect("validated record"))
                        .is_none()
                    {
                        incompatible = true;
                        return false;
                    }
                }
                matches.record(agent, line);
                if state.update(record).is_none() {
                    incompatible = true;
                    return false;
                }
                summary = Some(state);
                initial.clear();
            } else {
                initial.push(line.to_owned());
                if initial.len() == 50 {
                    return false;
                }
            }
        } else {
            let state = summary.as_mut().unwrap();
            matches.record(state.agent, line);
            if state.update(record).is_none() {
                incompatible = true;
                return false;
            }
        }
        if let Some(state) = &summary {
            if state.agent != Agent::Pi
                && !state.result.cwd.is_empty()
                && cwd.is_some_and(|here| here != state.result.cwd)
            {
                excluded = true;
                return false;
            }
        }
        true
    })?;
    if incompatible {
        return fallback(path, mtime, query);
    }
    if excluded {
        return None;
    }
    let session = summary?.finish(mtime);
    matches.finish(&session).then_some(session)
}

struct Summary {
    result: Session,
    first_user: String,
    agent: Agent,
}

impl Summary {
    fn new(path: &Path, agent: Agent) -> Self {
        Self {
            result: Session {
                path: path.to_string_lossy().into_owned(),
                id: if agent == Agent::Claude {
                    path.file_stem()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .into_owned()
                } else {
                    String::new()
                },
                agent: agent.name(),
                cwd: String::new(),
                last_activity: 0,
                model: String::new(),
                title: String::new(),
            },
            first_user: String::new(),
            agent,
        }
    }

    fn update(&mut self, record: Record<'_>) -> Option<()> {
        let result = &mut self.result;
        let first_user = &mut self.first_user;
        let agent = self.agent;
        if let Some(stamp) = text(&record.timestamp).and_then(|s| adapters::parse_timestamp(&s)) {
            result.last_activity = result.last_activity.max(stamp);
        }
        let kind = text(&record.kind).unwrap_or_default();
        match agent {
            Agent::Claude => {
                if result.cwd.is_empty() {
                    if let Some(cwd) = text(&record.cwd) {
                        result.cwd = cwd.to_owned();
                    }
                }
                if kind == "ai-title" {
                    if let Some(title) = text(&record.title) {
                        result.title = title.to_owned();
                    }
                }
                if matches!(kind, "user" | "assistant") {
                    if let Some(message) = record.message {
                        if result.model.is_empty() {
                            if let Some(model) = text(&message.model) {
                                result.model = model.to_owned();
                            }
                        }
                        if kind == "user" && first_user.is_empty() {
                            if let Some(content) = content_text(&message.content) {
                                *first_user = flatten(&content);
                            }
                        }
                    }
                }
            }
            Agent::Pi => match kind {
                "session" => {
                    if let Some(cwd) = text(&record.cwd) {
                        result.cwd = cwd.to_owned();
                    }
                    if let Some(id) = text(&record.id) {
                        result.id = id.to_owned();
                    }
                }
                "model_change" => {
                    result.model = format!(
                        "{}/{}",
                        text(&record.provider).as_deref().unwrap_or("?"),
                        text(&record.model_id).as_deref().unwrap_or("?")
                    );
                }
                "message" if first_user.is_empty() => {
                    if let Some(message) = record.message {
                        if text(&message.role).as_deref() == Some("user") {
                            if let Some(content) = message.content {
                                // Reuse the adapter for uncommon mixed content blocks.
                                let content: Value =
                                    serde_json::from_str(content.as_raw_str()).ok()?;
                                let message = serde_json::json!({"type":"message", "message":{"role":"user", "content":content}});
                                if let Some(turn) = adapters::pi::turns(&[message], false).first() {
                                    *first_user = turn.text.clone();
                                }
                            }
                        }
                    }
                }
                _ => {}
            },
            Agent::Codex => {
                if let Some(payload) = record.payload {
                    if result.id.is_empty() {
                        if let Some(id) = text(&payload.id) {
                            result.id = id.to_owned();
                        }
                    }
                    if result.cwd.is_empty() {
                        if let Some(cwd) = text(&payload.cwd) {
                            result.cwd = cwd.to_owned();
                        }
                    }
                    if let Some(model) = text(&payload.model) {
                        result.model = model.to_owned();
                    }
                    if first_user.is_empty()
                        && text(&payload.kind).as_deref() == Some("message")
                        && text(&payload.role).as_deref() == Some("user")
                    {
                        if let Some(content) = payload.content {
                            let content: Value = serde_json::from_str(content.as_raw_str()).ok()?;
                            *first_user = adapters::codex::user_title(&content);
                        }
                    }
                }
            }
        }
        Some(())
    }

    fn finish(mut self, mtime: i64) -> Session {
        self.result.title = if self.result.title.is_empty() {
            if self.agent == Agent::Codex {
                adapters::codex::session_title(self.first_user)
            } else {
                self.first_user
            }
        } else {
            flatten(&self.result.title)
        };
        if self.result.last_activity <= 0 {
            self.result.last_activity = mtime;
        }
        self.result
    }
}

fn fallback(path: &Path, mtime: i64, query: &crate::search::Query<'_>) -> Option<Session> {
    let (records, _) = crate::scan::parse_file(path)?;
    let agent = adapters::detect(&records)?;
    let session = adapters::summarize(agent, &path.to_string_lossy(), &records, mtime);
    let mut matches = crate::search::Matches::new(query);
    for record in &records {
        matches.text(&adapters::text(agent, record));
    }
    matches.finish(&session).then_some(session)
}
