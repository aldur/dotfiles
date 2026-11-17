//! The functions that make records readable for a person.

use std::path::Path;

use crate::adapters::{self, Agent};
use crate::context;
use crate::scan;
use crate::style;

/// One turn. The key is the value that the adapter gives.
pub fn turn(path: &Path, key: &str) -> String {
    selected_turn(path, key, None, false)
}

/// One presentation for preview and pager. Exports keep the original context.
pub fn readable(path: &Path, key: Option<&str>, expanded: bool, no_tools: bool) -> String {
    match key {
        Some(key) => selected_turn(path, key, Some(expanded), no_tools),
        None => conversation(path, no_tools, Some(expanded)),
    }
}

fn selected_turn(path: &Path, key: &str, expanded: Option<bool>, no_tools: bool) -> String {
    let Ok(index) = key.parse::<usize>() else {
        return format!("agent-log: bad turn key {key}\n");
    };
    let Some((agent, record)) = scan::turn_record(path, index) else {
        return format!("agent-log: no turn {key}\n");
    };
    render_record(agent, &record, no_tools, expanded)
}

fn render_record(
    agent: Agent,
    record: &serde_json::Value,
    no_tools: bool,
    expanded: Option<bool>,
) -> String {
    let (role, blocks) = adapters::blocks(agent, record, no_tools);
    let time = adapters::clock(
        record
            .get("timestamp")
            .and_then(serde_json::Value::as_str)
            .unwrap_or(""),
    );
    let technical =
        role.starts_with("tool") || matches!(role.as_str(), "thinking" | "system" | "developer");
    if let Some(expanded) = expanded.filter(|_| technical) {
        let text = blocks
            .into_iter()
            .map(|block| crate::model::sanitize(&block.text))
            .collect::<Vec<_>>()
            .join("\n\n");
        let text = if expanded && role.starts_with("tool") {
            serde_json::from_str::<serde_json::Value>(&text)
                .ok()
                .filter(|value| value.is_object() || value.is_array())
                .map(|value| serde_json::to_string_pretty(&value).unwrap_or_default())
                .unwrap_or(text)
        } else {
            text
        };
        return format!("{}\n", context::detail(&role, &text, expanded));
    }
    let body = blocks
        .into_iter()
        .map(|block| {
            let text = crate::model::sanitize(&block.text);
            let tool = block.label.as_deref().unwrap_or(&role).starts_with("tool");
            let text = if tool && expanded.is_none() && !style::enabled() {
                fence(&text)
            } else {
                text
            };
            match (expanded, block.label) {
                (Some(expanded), Some(label)) => context::detail(&label, &text, expanded),
                (Some(expanded), None) => context::render(&text, expanded),
                (None, Some(label)) => format!("{}\n{text}", style::heading(&label, "")),
                (None, None) => text,
            }
        })
        .collect::<Vec<_>>()
        .join("\n\n");
    format!(
        "{}\n\n{}\n",
        style::turn_heading(&role, &time),
        body.trim_end()
    )
}

/// Session metadata accompanies copied/exported turns, not every preview.
pub fn header(path: &Path) -> String {
    let Some(session) = scan::summarize_file(path) else {
        return String::new();
    };
    header_from(&session)
}

/// Colour shows that a person reads the output now. No colour shows that the
/// output goes to a file, a pager or glow, and all of them need markdown.
fn header_from(session: &crate::model::Session) -> String {
    let when = scan::format_when(session.last_activity);
    if !style::enabled() {
        let mut md = format!("# {}\n\n", session.title);
        md.push_str(&format!("- session: {}\n", session.id));
        if !session.model.is_empty() {
            md.push_str(&format!("- model: {}\n", session.model));
        }
        md.push_str(&format!("- when: {when} ({})\n", session.agent));
        if !session.cwd.is_empty() {
            md.push_str(&format!("- cwd: {}\n", session.cwd));
        }
        md.push('\n');
        return md;
    }
    let label = |name: &str| style::dim(name);
    let mut out = format!("{} {}\n", label("session:"), session.id);
    if !session.title.is_empty() {
        out.push_str(&format!(
            "{} {}\n",
            label("title:  "),
            style::bold(&crate::model::truncate(&session.title, 100))
        ));
    }
    if !session.model.is_empty() {
        out.push_str(&format!("{} {}\n", label("model:  "), session.model));
    }
    out.push_str(&format!(
        "{} {when}  {}\n",
        label("when:   "),
        style::dim(&format!("({})", session.agent))
    ));
    out.push_str(&style::rule());
    out.push_str("\n\n");
    out
}

/// Put tool input or output in a code block. Markdown would read `*` or `_`
/// in it as emphasis, and glow would remove them and the indentation.
fn fence(text: &str) -> String {
    let mut longest = 0;
    let mut run = 0;
    for ch in text.chars() {
        run = if ch == '`' { run + 1 } else { 0 };
        longest = longest.max(run);
    }
    let marks = "`".repeat(longest.max(2) + 1);
    format!("{marks}\n{}\n{marks}", text.trim_end_matches('\n'))
}

/// The full conversation, in sequence.
pub fn full(path: &Path, no_tools: bool) -> String {
    conversation(path, no_tools, None)
}

fn conversation(path: &Path, no_tools: bool, expanded: Option<bool>) -> String {
    let Some((records, mtime)) = scan::parse_file(path) else {
        return format!("agent-log: cannot read {}\n", path.display());
    };
    let Some(agent) = adapters::detect(&records) else {
        return format!("agent-log: {}: unrecognised format\n", path.display());
    };
    let session = adapters::summarize(agent, &path.to_string_lossy(), &records, mtime);
    let mut out = header_from(&session);
    for turn in adapters::turns(agent, &records, no_tools) {
        if let Some(record) = turn
            .key
            .parse::<usize>()
            .ok()
            .and_then(|index| index.checked_sub(1))
            .and_then(|i| records.get(i))
        {
            out.push_str(&render_record(agent, record, no_tools, expanded));
            out.push('\n');
        }
    }
    out
}
