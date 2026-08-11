//! The common shape of a transcript.
//!
//! Claude, pi and Codex record a conversation in different formats. The
//! records, the content blocks and the names of the roles are all different.
//! The rest of the program uses only the two structures below. Thus an adapter
//! is the only code that knows the format of a file.

/// One turn: a single user message, assistant reply, tool call or tool result.
pub struct Turn {
    /// The address of the turn in its file. Most formats use a line number.
    /// A proxy transcript uses an exchange id. Only the adapter reads it.
    pub key: String,
    /// For example `user`, `assistant`, `thinking` or `tool: bash`.
    /// The value is free text, because the agents use different names.
    pub kind: String,
    /// The time as HH:MM:SS. The value is empty if the record has no time.
    pub time: String,
    /// The single line that the picker shows.
    pub label: String,
    /// The full turn on one line. The search uses this text. The label is
    /// only for display.
    pub text: String,
}

/// One conversation, summarised for the session picker.
pub struct Session {
    pub path: String,
    /// The name that the agent gives to the conversation. A resume command
    /// takes this value. If the format records no name, use the file stem.
    pub id: String,
    /// `claude`, `pi`, `codex`, `wire`.
    pub agent: &'static str,
    /// The working directory of the conversation, if the format records it.
    /// The picker uses it to show only the sessions of the current project.
    pub cwd: String,
    /// The time of the last activity, in seconds from the epoch. The picker
    /// sorts on it. If the format records no time, use the file time.
    pub last_activity: i64,
    /// Rendered `YYYY-MM-DD HH:MM` of `last_activity`.
    pub when: String,
    pub model: String,
    /// The recorded title. If the format records no title, use the first
    /// message of the user.
    pub title: String,
    /// The text of all the turns, on one line. The search uses it.
    pub corpus: String,
}

/// Put a multi-line text on one line and remove the control sequences.
///
/// A transcript can contain the output of a terminal. Thus the text of a
/// session can contain escape sequences. These sequences change the colours of
/// the picker. A sequence such as `\x1b[2J` also erases the screen.
pub fn flatten(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last_was_space = false;
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\x1b' {
            skip_escape(&mut chars);
            continue;
        }
        let space = ch == '\n' || ch == '\r' || ch == '\t' || ch == ' ';
        if space {
            if !last_was_space {
                out.push(' ');
            }
        } else if ch.is_control() {
            // A summary line must not contain a backspace or a bell.
            continue;
        } else {
            out.push(ch);
        }
        last_was_space = space;
    }
    out.trim().to_string()
}

/// Move the iterator past one escape sequence. The caller consumed the
/// `\x1b` already. A CSI or an OSC sequence continues to its final byte.
/// All the other sequences have two characters.
fn skip_escape(chars: &mut std::iter::Peekable<std::str::Chars>) {
    match chars.peek() {
        Some('[') => {
            chars.next();
            while let Some(c) = chars.next() {
                if ('@'..='~').contains(&c) {
                    break;
                }
            }
        }
        Some(']') => {
            chars.next();
            while let Some(c) = chars.next() {
                if c == '\x07' || c == '\x1b' {
                    break;
                }
            }
        }
        _ => {
            chars.next();
        }
    }
}

/// Remove the control sequences and the control characters, and keep the
/// line structure.
///
/// The full and the turn views print a whole turn to the terminal, to fzf
/// or to a pager. A tool result can contain the output of a program, and
/// thus escape sequences. A sequence that passes without change can move
/// the cursor, erase the screen or write text into the terminal. Only the
/// line breaks and the tabs of the source survive.
pub fn sanitize(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\x1b' {
            skip_escape(&mut chars);
        } else if ch == '\n' || ch == '\t' || !ch.is_control() {
            out.push(ch);
        }
    }
    out
}

/// Cut the text at a character boundary. Do not divide a multi-byte
/// character.
pub fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    text.chars().take(max).collect()
}
