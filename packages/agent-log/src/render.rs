//! The functions that make records readable for a person.

use std::path::Path;

use crate::adapters::{self, Agent};
use crate::scan;
use crate::style;

/// Read metadata and only decode the selected record's content.
pub fn header_and_turn(path: &Path, key: &str) -> String {
    format!("{}{}", header(path), turn(path, key))
}

/// One turn. The key is the value that the adapter gives.
pub fn turn(path: &Path, key: &str) -> String {
    let Ok(index) = key.parse::<usize>() else {
        return format!("agent-log: bad turn key {key}\n");
    };
    let Some((agent, record)) = scan::turn_record(path, index) else {
        return format!("agent-log: no turn {key}\n");
    };
    let (role, body) = match agent {
        Agent::Claude => adapters::claude::render(&record, false),
        Agent::Pi => adapters::pi::render(&record, false),
        Agent::Codex => adapters::codex::render(&record),
    };
    format!(
        "{}\n\n{}\n",
        style::turn_heading(&role, ""),
        crate::model::sanitize(&body)
    )
}

/// The rule between the parts of the output. A blank line always comes after
/// it. Two different forms of the rule looked like a defect.
/// The header above a turn. It identifies the conversation. Thus a person can
/// find the source of a copied part.
pub fn header(path: &Path) -> String {
    let Some(session) = scan::summarize_file(path, &[]) else {
        return String::new();
    };
    header_from(&session)
}

fn header_from(session: &crate::model::Session) -> String {
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
        "{} {}  {}\n",
        label("when:   "),
        scan::format_when(session.last_activity),
        style::dim(&format!("({})", session.agent))
    ));
    out.push_str(&style::rule());
    out.push_str("\n\n");
    out
}

/// The full conversation, in sequence.
pub fn full(path: &Path, no_tools: bool) -> String {
    let Some((records, mtime)) = scan::parse_file(path) else {
        return format!("agent-log: cannot read {}\n", path.display());
    };
    let Some(agent) = adapters::detect(&records) else {
        return format!("agent-log: {}: unrecognised format\n", path.display());
    };
    let session = adapters::summarize(agent, &path.to_string_lossy(), &records, mtime);

    // Colour shows that a person reads the output now. Thus use the same
    // header as the turn view. No colour shows that the output goes to a file,
    // a pager or glow. All of them need markdown.
    let mut out = if style::enabled() {
        header_from(&session)
    } else {
        let mut md = format!("# {}\n\n", session.title);
        md.push_str(&format!(
            "_{} · {} · {}_\n",
            session.agent,
            if session.model.is_empty() {
                "?"
            } else {
                &session.model
            },
            scan::format_when(session.last_activity)
        ));
        if !session.cwd.is_empty() {
            md.push_str(&format!("_cwd {}_\n", session.cwd));
        }
        md
    };

    // Show the limits of a format together with its data.
    let caveat = match agent {
        // Without this text, a person can conclude that pi sent no system
        // prompt.
        Agent::Pi => Some(
            "A pi session records turns only — no system prompt, tool schemas or \
             rendered string.",
        ),
        Agent::Codex => Some(
            "The Codex reader is built from the published rollout format and has \
             not been checked against a real session.",
        ),
        _ => None,
    };
    if let Some(text) = caveat {
        if style::enabled() {
            out.push_str(&format!("{}\n", style::dim(text)));
        } else {
            out.push_str(&format!("\n> {text}\n"));
        }
    }

    // Put exactly one blank line between the header and the first turn.
    while !out.ends_with("\n\n") {
        out.push('\n');
    }

    for turn in adapters::turns(agent, &records, no_tools) {
        // `turn.text` is the single line for the search. It contains no line
        // breaks. Thus the conversation view uses the adapter again.
        let body = turn
            .key
            .parse::<usize>()
            .ok()
            .and_then(|index| index.checked_sub(1))
            .and_then(|i| records.get(i))
            .map(|record| match agent {
                Agent::Claude => adapters::claude::render(record, no_tools).1,
                Agent::Pi => adapters::pi::render(record, no_tools).1,
                Agent::Codex => adapters::codex::render(record).1,
            })
            .unwrap_or_else(|| turn.text.clone());
        let body = crate::model::sanitize(&body);
        let heading = style::turn_heading(&turn.kind, &turn.time);
        out.push_str(&format!("{heading}\n\n{body}\n\n"));
    }
    out
}
