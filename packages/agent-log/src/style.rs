//! The colour setting. The program makes the decision one time.
//!
//! Four conditions need three different answers. Thus this is a setting and
//! not a test of the output at each place that writes text:
//!
//!   * output to a terminal: use colour.
//!   * output to a pipe or a file: use no colour. If not, the file gets
//!     escape sequences.
//!   * `--pretty`: use no colour, because glow or bat adds its own.
//!   * an fzf preview: use colour, because fzf shows escape sequences. The
//!     output is a pipe, thus the preview command asks for colour.

use std::io::IsTerminal;
use std::sync::atomic::{AtomicBool, Ordering};

static ENABLED: AtomicBool = AtomicBool::new(false);

pub fn enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

pub fn set(enabled: bool) {
    ENABLED.store(enabled, Ordering::Relaxed);
}

/// `auto` obeys the terminal. `NO_COLOR` has priority over all the values.
pub fn resolve(choice: Option<&str>) -> bool {
    if std::env::var_os("NO_COLOR").is_some() {
        return false;
    }
    match choice {
        Some("always") => true,
        Some("never") => false,
        _ => std::io::stdout().is_terminal(),
    }
}

fn paint(code: &str, text: &str) -> String {
    if ENABLED.load(Ordering::Relaxed) {
        format!("\x1b[{code}m{text}\x1b[0m")
    } else {
        text.to_string()
    }
}

pub fn bold(text: &str) -> String {
    paint("1", text)
}
pub fn dim(text: &str) -> String {
    paint("2", text)
}
pub fn user(text: &str) -> String {
    paint("1;33", text)
}
pub fn assistant(text: &str) -> String {
    paint("1;36", text)
}
pub fn thinking(text: &str) -> String {
    paint("2;3", text)
}
pub fn cyan(text: &str) -> String {
    paint("36", text)
}
pub fn tool(text: &str) -> String {
    paint("35", text)
}
pub fn result(text: &str) -> String {
    paint("32", text)
}

/// The width of a rule. An ioctl call needs a libc dependency. Thus read the
/// width from the environment. fzf gives the width of a preview, and a shell
/// usually sets COLUMNS.
pub fn width() -> usize {
    for key in ["FZF_PREVIEW_COLUMNS", "COLUMNS"] {
        if let Some(value) = std::env::var_os(key) {
            if let Ok(columns) = value.to_string_lossy().parse::<usize>() {
                return columns.clamp(24, 100);
            }
        }
    }
    64
}

pub fn rule() -> String {
    dim(&"─".repeat(width()))
}

/// The heading of a block in a turn: the thinking, a tool call or a tool
/// result. With colour, it has a bar in the colour of the role, the name of
/// the role, and the time. Without colour, it is a markdown sub-heading,
/// because the output goes to a file, a pager or glow.
pub fn heading(role: &str, time: &str) -> String {
    styled_heading("###", role, time)
}

/// The heading of a turn. It is one level above the heading of a block.
pub fn turn_heading(role: &str, time: &str) -> String {
    styled_heading("##", role, time)
}

fn styled_heading(level: &str, role: &str, time: &str) -> String {
    if !enabled() {
        return if time.is_empty() {
            format!("{level} {role}")
        } else {
            format!("{level} {role} · {time}")
        };
    }
    let colour: fn(&str) -> String = match role {
        r if r.contains("user") => user,
        r if r.contains("thinking") => thinking,
        r if r.contains("result") => result,
        r if r.contains("tool") => tool,
        _ => assistant,
    };
    let label = colour(&format!("▌ {role}"));
    if time.is_empty() {
        label
    } else {
        format!("{label}  {}", dim(time))
    }
}
