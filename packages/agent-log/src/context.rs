//! Display-only parsing of injected context. Search and exports keep the source.

use crate::style;

pub struct Context<'a> {
    heading: Option<&'a str>,
    pub tag: &'a str,
    pub body: &'a str,
    pub rest: &'a str,
    pub complete: bool,
}

pub fn is_setup(tag: &str) -> bool {
    tag.ends_with("_instructions")
        || matches!(
            tag,
            "INSTRUCTIONS"
                | "environment_context"
                | "permissions"
                | "collaboration_mode"
                | "multi_agent_role"
                | "multi_agent_mode"
                | "tools"
                | "context_window"
                | "context_window_guidance"
                | "system-reminder"
        )
}

/// Read a leading tag pair, including nested pairs with the same name.
/// These are transcript wrappers, not a general-purpose XML document format.
pub fn prefix(text: &str) -> Option<Context<'_>> {
    let mut text = text.trim_start();
    let mut heading = None;
    if text.starts_with("# AGENTS.md instructions for ") {
        let (title, body) = text.split_once('\n')?;
        heading = Some(title);
        text = body.trim_start();
        if !text.starts_with("<INSTRUCTIONS>") {
            return None;
        }
    }
    let opening = text.strip_prefix('<')?;
    let name_end = opening.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-'))?;
    let tag = &opening[..name_end];
    if tag.is_empty() || !tag.as_bytes()[0].is_ascii_alphabetic() {
        return None;
    }
    let start = text.find('>')? + 1;
    if text[..start].ends_with("/>") {
        return None;
    }
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    let mut depth = 1;
    let mut cursor = start;
    while let Some(offset) = text[cursor..].find('<') {
        let at = cursor + offset;
        let tail = &text[at..];
        if tail.starts_with(&close) {
            depth -= 1;
            if depth == 0 {
                return Some(Context {
                    heading,
                    tag,
                    body: &text[start..at],
                    rest: &text[at + close.len()..],
                    complete: true,
                });
            }
        } else if tail
            .strip_prefix(&open)
            .is_some_and(|s| s.starts_with('>') || s.starts_with(char::is_whitespace))
            && !tail
                .split_once('>')
                .is_some_and(|(tag, _)| tag.trim_end().ends_with('/'))
        {
            depth += 1;
        }
        cursor = at + 1;
    }
    Some(Context {
        heading,
        tag,
        body: &text[start..],
        rest: "",
        complete: false,
    })
}

fn label(tag: &str) -> String {
    match tag {
        "INSTRUCTIONS" => "Project instructions".into(),
        "skills_instructions" => "Skills".into(),
        "environment_context" => "Environment".into(),
        _ => {
            let mut label = tag.replace(['_', '-'], " ");
            label[..1].make_ascii_uppercase();
            label
        }
    }
}

pub fn render(text: &str, expanded: bool) -> String {
    render_inner(text, expanded, 0)
}

fn render_inner(mut text: &str, expanded: bool, depth: usize) -> String {
    let mut out = String::new();
    let mut fence = None;
    while !text.is_empty() {
        let line_end = text.find('\n').map_or(text.len(), |i| i + 1);
        let line = &text[..line_end];
        let trimmed = line.trim_start();
        let marker = trimmed
            .as_bytes()
            .first()
            .copied()
            .filter(|c| matches!(c, b'`' | b'~'));
        let run = marker.map_or(0, |marker| {
            trimmed.bytes().take_while(|c| *c == marker).count()
        });
        if run >= 3 {
            let marker = marker.unwrap();
            match fence {
                Some((open, length))
                    if open == marker && run >= length && trimmed[run..].trim().is_empty() =>
                {
                    fence = None
                }
                None => fence = Some((marker, run)),
                _ => {}
            }
        } else if fence.is_none() && depth < 16 {
            if let Some(block) = prefix(text) {
                if block.complete && (depth > 0 || is_setup(block.tag)) {
                    if depth > 0 && !block.body.contains(['\n', '<']) {
                        out.push_str(&format!(
                            "{}: {}\n",
                            style::dim(&label(block.tag)),
                            block.body.trim()
                        ));
                    } else {
                        let label = block
                            .heading
                            .and_then(|h| h.strip_prefix("# AGENTS.md instructions for "))
                            .map_or_else(
                                || label(block.tag),
                                |path| format!("Project instructions · {path}"),
                            );
                        out.push_str(&detail_inner(
                            &label,
                            block.body.trim(),
                            expanded,
                            depth + 1,
                        ));
                        out.push('\n');
                    }
                    text = block.rest.strip_prefix('\n').unwrap_or(block.rest);
                    continue;
                }
            }
        }
        out.push_str(line);
        text = &text[line_end..];
    }
    out
}

pub fn detail(label: &str, text: &str, expanded: bool) -> String {
    detail_inner(label, text, expanded, 1)
}

fn detail_inner(label: &str, text: &str, expanded: bool, depth: usize) -> String {
    if !expanded {
        return style::dim(&format!(
            "▸ {label} · {} lines",
            text.lines().count().max(1)
        ));
    }
    let body = render_inner(text, true, depth);
    format!(
        "{}\n{}",
        style::bold(&format!("▾ {label}")),
        body.lines()
            .map(|line| format!("  {line}"))
            .collect::<Vec<_>>()
            .join("\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn context_is_folded_without_eating_surrounding_text() {
        let text = "Before\n<skills_instructions>\nSecret details\n</skills_instructions>\nAfter";
        let folded = render(text, false);
        assert!(folded.contains("▸ Skills"));
        assert!(!folded.contains("Secret details"));
        assert!(folded.starts_with("Before\n"));
        assert!(folded.ends_with("After"));
        let expanded = render(text, true);
        assert!(expanded.contains("▾ Skills"));
        assert!(expanded.contains("Secret details"));
        assert!(!expanded.contains("<skills_instructions>"));
        let project =
            "# AGENTS.md instructions for /tmp/project\n<INSTRUCTIONS>rules</INSTRUCTIONS>";
        assert!(render(project, true).contains("Project instructions · /tmp/project"));
    }

    #[test]
    fn nested_fields_and_same_name_blocks() {
        let text =
            "<environment_context><cwd>/tmp/project</cwd><shell>bash</shell></environment_context>";
        assert!(render(text, true).contains("Cwd: /tmp/project"));
        assert!(render(text, true).contains("Shell: bash"));
        let nested = "<tools><tools>inner</tools>outer</tools>tail";
        let block = prefix(nested).unwrap();
        assert_eq!(block.body, "<tools>inner</tools>outer");
        assert_eq!(block.rest, "tail");
        assert!(
            prefix("<tools><tools name='nested' /></tools>")
                .unwrap()
                .complete
        );
    }

    #[test]
    fn literal_code_unknown_tags_and_incomplete_blocks_stay_visible() {
        for text in [
            "```xml\n<skills_instructions>literal</skills_instructions>\n```",
            "An inline <skills_instructions>example</skills_instructions>",
            "<example>not injected context</example>",
            "<skills_instructions>unfinished",
            "````xml\n```\n<skills_instructions>literal</skills_instructions>\n````",
        ] {
            assert_eq!(render(text, false), text);
        }
    }
}
