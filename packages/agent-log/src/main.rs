//! agent-log shows the conversations of Claude Code, pi and Codex in one
//! picker.
//!
//! This program reads the files, summarizes them and shows the text. fzf makes
//! the selection. The key commands of fzf start this program again with the
//! hidden subcommands that have a name with the prefix `_`. The prompt of fzf
//! holds the state of the picker. Thus no state files are necessary.

use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

mod adapters;
mod context;
mod metadata;
mod model;
mod render;
mod scan;
mod search;
mod source;
mod style;

use adapters::Agent;

const USAGE: &str = "\
agent-log — browse Claude Code, pi and Codex conversations

Usage: agent-log [options] [PATH]

PATH is a transcript or a directory. A transcript (any supported format,
detected by content) opens its turns. A directory limits the picker to the
conversations recorded in it. Without PATH, the picker shows the
conversations of the current directory.

Options:
  --all             Every project, not just the current directory
  --agent <name>    Only claude, pi or codex
  --query <text>    Start with this search
  --no-tools        Hide tool calls and results
  --show-model      Show the model in conversation rows
  --newest          Take the most recent conversation and print it (no picker)
  --full            Print the whole conversation
  --turn <n>        Print turn n as numbered by --list (negative counts from the end)
  --list            Print the picker rows instead of running fzf
  --plain           Do not render markdown with glow or bat
  --color <when>    always, never or auto (default: auto; NO_COLOR is honoured)
  -h, --help        Show this help

Output: on a terminal, agent-log renders markdown with glow or bat, and
--full uses a pager. In a pipe, the output is plain markdown.

Search: exact by default. Each space-separated word must occur, in any case.
A conversation matches on its title and all its text, including thinking and
tool traffic. A turn matches on its own text. ctrl-s switches to the fuzzy
search of fzf on the title or the turn text. The prompt shows the state.

Rows are newest first. Printed turns and --full are in chronological order.
No caches or indexes: every request reads the original transcripts.
";

const SESSION_HELP: &str = "enter             open conversation
alt-s             this project / all projects
alt-m             show/hide model";
const TURN_HELP: &str = "enter             print selected turns (or the focused turn)
tab / shift-tab   mark/unmark turns";
const COMMON_HELP: &str = "ctrl-o            print whole conversation and exit
alt-a             whole conversation in pager
alt-v             whole conversation in nvim
alt-i             print session id and exit
ctrl-s            exact/fuzzy search
ctrl-t            show/hide tools
alt-e             expand/collapse context, thinking and tool details
alt-p             show/hide preview
alt-w             wrap/unwrap rows
alt-g / alt-G     oldest / newest row
pgup/pgdn         scroll preview by a page
shift-up/down     scroll preview by a line (also alt-up/down)
mouse wheel       scroll the pane under the pointer
ctrl-/            show/hide help (also alt-h or f1)
esc               close picker";

fn usage() -> String {
    format!(
        "{USAGE}\nConversation picker:\n{SESSION_HELP}\n\nTurn picker:\n{TURN_HELP}\n\n\
         Both pickers:\n{COMMON_HELP}\n"
    )
}

#[derive(Default)]
struct Options {
    all: bool,
    agent: Option<Agent>,
    newest: bool,
    full: bool,
    list: bool,
    show_model: bool,
    plain: bool,
    no_tools: bool,
    turn: Option<i64>,
    color: Option<String>,
    query: String,
    target: Option<PathBuf>,
}

/// The state of a picker. The prompt shows it, for example
/// `all projects · dialogue · fuzzy> `, and the key commands read it from
/// `FZF_PROMPT`.
#[derive(Clone, Copy, Default)]
struct State {
    turns: bool,
    all: bool,
    dialogue: bool,
    fuzzy: bool,
    details: bool,
}

impl State {
    fn prompt(self) -> String {
        let mut words = vec![match (self.turns, self.all) {
            (true, _) => "turns",
            (false, true) => "all projects",
            (false, false) => "this project",
        }];
        for (on, word) in [
            (self.dialogue, "dialogue"),
            (self.fuzzy, "fuzzy"),
            (self.details, "details"),
        ] {
            if on {
                words.push(word);
            }
        }
        format!("{}> ", words.join(" · "))
    }

    fn parse(prompt: &str) -> Self {
        let prompt = prompt.trim_end().trim_end_matches('>');
        let words: Vec<&str> = prompt.split(" · ").map(str::trim).collect();
        let has = |word| words.contains(&word);
        State {
            turns: has("turns"),
            all: has("all projects"),
            dialogue: has("dialogue"),
            fuzzy: has("fuzzy"),
            details: has("details"),
        }
    }

    fn current() -> Self {
        std::env::var("FZF_PROMPT")
            .map(|prompt| Self::parse(&prompt))
            .unwrap_or_default()
    }
}

/// Write text to the output.
///
/// Rust disables SIGPIPE. Thus `println!` to a closed pipe stops the program
/// with an error. A command such as `agent-log --list | head` closes the pipe.
/// This function stops the program without an error.
fn emit(text: &str) {
    use std::io::ErrorKind;
    let mut out = std::io::stdout().lock();
    match out.write_all(text.as_bytes()).and_then(|_| out.flush()) {
        Err(e) if e.kind() == ErrorKind::BrokenPipe => std::process::exit(0),
        _ => {}
    }
}

fn emit_rows(rows: &[String]) {
    if !rows.is_empty() {
        emit(&format!("{}\n", rows.join("\n")));
    }
}

fn fail(message: &str) -> ! {
    eprintln!("agent-log: {message}");
    std::process::exit(2);
}

fn parse_args(args: &[String]) -> Options {
    let mut opts = Options::default();
    let mut index = 0;
    while index < args.len() {
        let arg = args[index].as_str();
        let mut next = || {
            index += 1;
            args.get(index)
                .cloned()
                .unwrap_or_else(|| fail(&format!("{arg} needs a value")))
        };
        match arg {
            "-h" | "--help" => {
                emit(&usage());
                std::process::exit(0);
            }
            "--all" => opts.all = true,
            "--newest" => opts.newest = true,
            "--full" => opts.full = true,
            "--list" => opts.list = true,
            "--show-model" => opts.show_model = true,
            "--plain" => opts.plain = true,
            "--no-tools" => opts.no_tools = true,
            "--color" => opts.color = Some(next()),
            "--query" => opts.query = next(),
            other if other.starts_with("--color=") => {
                opts.color = Some(other.trim_start_matches("--color=").to_string())
            }
            "--agent" => {
                let name = next();
                opts.agent = Some(
                    Agent::parse(&name).unwrap_or_else(|| fail(&format!("unknown agent: {name}"))),
                );
            }
            "--turn" => {
                let value = next();
                opts.turn =
                    Some(value.parse().unwrap_or_else(|_| {
                        fail(&format!("--turn wants an integer, got {value}"))
                    }));
            }
            other if other.starts_with("--") => fail(&format!("unknown flag: {other}")),
            other => {
                if opts.target.is_some() {
                    fail(&format!("extra argument: {other}"));
                }
                opts.target = Some(PathBuf::from(other));
            }
        }
        index += 1;
    }
    opts
}

/// The value of `--color` at any position. The hidden subcommands read their
/// arguments directly.
fn colour_choice(argv: &[String]) -> Option<&str> {
    if let Some(inline) = argv.iter().find_map(|a| a.strip_prefix("--color=")) {
        return Some(inline);
    }
    argv.iter()
        .position(|a| a == "--color")
        .and_then(|i| argv.get(i + 1))
        .map(String::as_str)
}

fn home() -> PathBuf {
    std::env::var("HOME").map(PathBuf::from).unwrap_or_default()
}

/// The sessions to list, and whether they come from all the projects.
///
/// A directory other than the home of the user can hold the directories of
/// the agents, like a home that ~/Work/evals keeps from a run. Then list all
/// the conversations in it. Only the contents of the directory decide, not
/// the query, so a search cannot change the scope.
fn find_sessions(opts: &Options, cwd: &Path) -> (Vec<model::Session>, bool) {
    let stores = scan::other_home_roots(cwd);
    let user_home = home().canonicalize().unwrap_or_else(|_| home());
    if cwd != user_home && stores.iter().any(|(_, root)| root.is_dir()) {
        return (collect_sessions(opts, cwd, stores, true), true);
    }
    (
        collect_sessions(opts, cwd, scan::roots(&home()), opts.all),
        opts.all,
    )
}

fn collect_sessions(
    opts: &Options,
    cwd: &Path,
    roots: Vec<(Agent, PathBuf)>,
    all: bool,
) -> Vec<model::Session> {
    let mut paths = Vec::new();
    // A scoped run is the usual command, and it removes most of the sessions
    // that a full read collects. Thus ignore the directories that cannot
    // agree, and read only the sessions of this project.
    let candidates = (!all).then(|| scan::project_dir_candidates(cwd));
    for (agent, root) in roots {
        if opts.agent.is_some_and(|want| want != agent) {
            continue;
        }
        scan::find_jsonl_filtered(&root, candidates.as_deref(), &mut paths);
    }
    let here = cwd.to_string_lossy();
    scan::summarize_all(
        &paths,
        opts.agent,
        &scan::search_terms(&opts.query),
        (!all).then_some(here.as_ref()),
    )
}

#[derive(Clone, Copy)]
enum SessionLayout {
    Picker,
    List { show_model: bool },
}

/// Search full text on demand. Keep paths and IDs in fields 2 and 4.
fn session_rows(
    sessions: &[model::Session],
    show_project: bool,
    layout: SessionLayout,
) -> Vec<String> {
    let model_width = sessions
        .iter()
        .map(|s| model::flatten(&s.model).chars().count())
        .max()
        .unwrap_or(1)
        .max(1);
    sessions
        .iter()
        .map(|s| {
            let project = if show_project {
                let name = Path::new(&s.cwd)
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default();
                format!("{} ", style::dim(&format!("[{name}]")))
            } else {
                String::new()
            };
            let prefix = format!(
                "{}  {} {}",
                style::dim(&scan::format_when(s.last_activity)),
                style::dim(&format!("{:<6}", s.agent)),
                project
            );
            let name = model::flatten(&s.model);
            let name = if name.is_empty() { "?" } else { &name };
            let model_label = format!("[{name}]");
            let model = style::dim(&format!("{model_label:<width$} ", width = model_width + 2));
            match layout {
                SessionLayout::Picker => {
                    // Separate fields let fzf hide the model without a reload.
                    format!("{prefix}\t{}\t{}\t{}\t{model}", s.path, s.title, s.id)
                }
                SessionLayout::List { show_model } => format!(
                    "{prefix}{}{}\t{}\t\t{}",
                    if show_model { &model } else { "" },
                    s.title,
                    s.path,
                    s.id
                ),
            }
        })
        .collect()
}

/// The turns in chronological order: the position, the record key, and the
/// kind, time and text fields. With search terms, keep only the turns that
/// contain all of them, and start the text near the first match.
fn turn_rows(path: &Path, no_tools: bool, terms: &[String]) -> Vec<(usize, String, String)> {
    scan::turns(path, no_tools)
        .unwrap_or_else(|| fail(&format!("cannot read transcript {}", path.display())))
        .into_iter()
        .enumerate()
        .filter(|(_, t)| search::contains_all(&t.text, terms))
        .map(|(index, t)| {
            // Without terms, keep all text: fzf searches the row in the fuzzy
            // mode. The UI clips rows instead of hiding body fields with
            // --with-nth (which would also hide matches).
            let text = if terms.is_empty() {
                t.text.clone()
            } else {
                excerpt(&t.text, terms)
            };
            (
                index + 1,
                t.key.clone(),
                format!(
                    "{}\t{}\t{text}",
                    style::dim(&format!("{:<14}", model::truncate(&t.kind, 14))),
                    style::dim(&format!("{:>8}", t.time)),
                ),
            )
        })
        .collect()
}

/// The text from shortly before the first match, with the matches marked.
/// This program does the exact search, thus fzf marks no matches.
fn excerpt(text: &str, terms: &[String]) -> String {
    let ranges = search::ranges(text, terms);
    let Some(&(first, _)) = ranges.first() else {
        return text.to_string();
    };
    let start = text[..first]
        .char_indices()
        .rev()
        .nth(30)
        .map_or(0, |(index, _)| index);
    let mut out = String::from(if start > 0 { "…" } else { "" });
    let mut at = start;
    for (from, to) in ranges {
        out.push_str(&text[at..from]);
        out.push_str(&style::matched(&text[from..to]));
        at = to;
    }
    out.push_str(&text[at..]);
    out
}

/// Write markdown. On a terminal, render it with glow or bat, in a pager if
/// `paged`. These programs change the line breaks, and this makes a file
/// incorrect. Thus a pipe gets the text without changes.
fn show(text: &str, render: bool, paged: bool) {
    if !std::io::stdout().is_terminal() {
        emit(text);
        return;
    }
    if render {
        let renderers: [(&str, &[&str]); 2] = if paged {
            [
                ("glow", &["-p", "-"]),
                (
                    "bat",
                    &["--language=markdown", "--style=plain", "--paging=always"],
                ),
            ]
        } else {
            [
                ("glow", &["-"]),
                (
                    "bat",
                    &["--language=markdown", "--style=plain", "--paging=never"],
                ),
            ]
        };
        for (program, args) in renderers {
            if pipe_through(program, args, text) {
                return;
            }
        }
    }
    if paged {
        page(text);
    } else {
        emit(text);
    }
}

/// Render markdown only on a terminal and without --plain. Colour applies to
/// the text that is not rendered.
fn output_style(plain: bool, colour: Option<&str>) -> bool {
    let render = !plain && std::io::stdout().is_terminal();
    style::set(!render && style::resolve(colour));
    render
}

fn page(text: &str) {
    if let Ok(pager) = std::env::var("PAGER") {
        if !pager.trim().is_empty() && pipe_through("sh", &["-c", &pager], text) {
            return;
        }
    }
    if pipe_through("less", &["-R"], text) {
        return;
    }
    emit(text);
}

/// Quote a value for use inside an fzf action string. fzf gives the
/// action to `$SHELL -c`. A transcript path contains the name of the
/// project directory, and that name can contain `$(…)`, a backtick or a
/// quote. Single quotes make the value literal; `'\''` gives one literal
/// quote.
fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', "'\\''"))
}

/// Write the conversation to a private file and open nvim on it. A fixed
/// name in /tmp is not safe: an other user can predict the name, put a
/// symbolic link there, or read the transcript. Thus create the file with
/// `O_EXCL` and mode 0600, prefer `XDG_RUNTIME_DIR`, and remove the file
/// after nvim stops.
fn view_in_nvim(text: &str) {
    use std::os::unix::fs::OpenOptionsExt;
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .ok()
        .filter(|d| d.is_dir())
        .unwrap_or_else(std::env::temp_dir);
    for attempt in 0..100 {
        let path = dir.join(format!("agent-log-{}-{attempt}.md", std::process::id()));
        let mut file = match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(file) => file,
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => fail(&format!("cannot create {}: {e}", path.display())),
        };
        let _ = file.write_all(text.as_bytes());
        drop(file);
        let _ = Command::new("nvim").arg("-R").arg(&path).status();
        let _ = std::fs::remove_file(&path);
        return;
    }
    fail("cannot create a temporary file");
}

/// Send `text` to the input of a command. The result is false if the program
/// is not available. Then the caller can try the next program.
fn pipe_through(program: &str, args: &[&str], text: &str) -> bool {
    let Ok(mut child) = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .spawn()
    else {
        return false;
    };
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let _ = child.wait();
    true
}

#[derive(Clone, Copy, PartialEq)]
enum Picker {
    Sessions,
    Turns,
}

/// The commands that a picker gives to fzf. `rows` gets the query and reads
/// the state from the prompt. `conversation` is the transcript, as a path or
/// as a field of the focused row.
struct Commands {
    rows: String,
    preview: String,
    conversation: String,
}

/// The result of a picker: the query, the key that closed it, its state and
/// the selected rows.
struct Picked {
    query: String,
    action: String,
    state: State,
    rows: Vec<String>,
}

fn run_fzf(
    exe: &str,
    rows: &[String],
    picker: Picker,
    state: State,
    query: &str,
    commands: &Commands,
    args: &[String],
) -> Option<Picked> {
    let exe = shell_quote(exe);
    // The tools change the preview of a conversation, and the rows of a
    // turn picker.
    let (help, footer, hidden, tools) = match picker {
        Picker::Sessions => (
            SESSION_HELP,
            "enter open",
            ",hidden",
            "refresh-preview".to_string(),
        ),
        Picker::Turns => (
            TURN_HELP,
            "enter print",
            "",
            format!("reload({})+first", commands.rows),
        ),
    };
    let mut child = Command::new("fzf")
        .args([
            "--style=minimal",
            "--reverse",
            "--ansi",
            "--delimiter=\t",
            "--no-sort",
            "-i",
            "--nth=-1",
            "--no-wrap",
            "--no-hscroll",
            "--info=inline-right",
            "--no-separator",
            "--padding=1,2",
            "--gap=0",
            "--tabstop=2",
            "--pointer=›",
            "--marker=●",
            "--color=fg+:-1,bg+:-1,prompt:-1,header:dim,footer:dim",
            "--ghost=Search · newest first",
            "--header-first",
            "--footer-border=none",
            "--print-query",
            "--bind=start:hide-header+first",
            "--bind=f1:toggle-header",
            "--bind=alt-h:toggle-header",
            "--bind=ctrl-/:toggle-header",
            "--bind=alt-w:toggle-wrap",
            "--bind=alt-p:toggle-preview",
            "--bind=alt-g:last,alt-G:first",
            // Paging the list changes the focused row and restarts its
            // preview. These bindings scroll the existing preview instead.
            "--bind=pgup:preview-page-up,pgdn:preview-page-down",
            "--bind=shift-up:preview-up,shift-down:preview-down",
            "--bind=alt-up:preview-up,alt-down:preview-down",
            "--bind=preview-scroll-up:preview-up,preview-scroll-down:preview-down",
            "--wrap-sign=↳ ",
            "--ellipsis=…",
        ])
        .arg(format!("--prompt={}", state.prompt()))
        .arg(format!("--query={query}"))
        .args(state.fuzzy.then_some("--bind=start:+unbind(change)"))
        .args((!state.fuzzy).then_some("--disabled"))
        .arg(format!("--header={help}\n{COMMON_HELP}"))
        .arg(format!(
            "--footer={footer} · ctrl-o print all · alt-a page · ctrl-s fuzzy · ctrl-/ help"
        ))
        .arg(format!("--preview={}", commands.preview))
        .arg(format!(
            "--preview-window=right,55%,wrap,border-left{hidden},<60(down,50%,border-top{hidden})"
        ))
        .arg(format!("--bind=change:reload({})", commands.rows))
        .arg(format!(
            "--bind=ctrl-s:transform({exe} _toggle fuzzy)+reload({})",
            commands.rows
        ))
        .arg(format!(
            "--bind=ctrl-t:transform({exe} _toggle dialogue)+{tools}"
        ))
        .arg(format!(
            "--bind=alt-e:transform({exe} _toggle details)+refresh-preview+show-preview"
        ))
        .arg(format!(
            "--bind=alt-a:execute({exe} _page {})",
            commands.conversation
        ))
        .arg(format!(
            "--bind=alt-v:execute({exe} _view {})",
            commands.conversation
        ))
        .arg(format!("--bind=enter:transform({exe} _accept enter)"))
        .arg(format!("--bind=ctrl-o:transform({exe} _accept all)"))
        .arg(format!("--bind=alt-i:transform({exe} _accept id)"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| fail(&format!("cannot run fzf: {e}")));
    {
        let stdin = child.stdin.as_mut().expect("piped");
        for row in rows {
            if writeln!(stdin, "{row}").is_err() {
                break;
            }
        }
    }
    let output = child.wait_with_output().ok()?;
    if !output.status.success() {
        return None;
    }
    // `--print-query` writes the query first. `_accept` adds the key and the
    // prompt. The selected rows follow.
    let text = String::from_utf8_lossy(&output.stdout);
    let mut lines = text.lines().map(str::to_string);
    let query = lines.next()?;
    let action = lines.next()?;
    let state = State::parse(&lines.next()?);
    let rows: Vec<String> = lines.filter(|line| !line.is_empty()).collect();
    (!rows.is_empty()).then_some(Picked {
        query,
        action,
        state,
        rows,
    })
}

/// The key commands of fzf. They read the state from `FZF_PROMPT`.
fn hidden_command(argv: &[String]) {
    let arg = |index: usize, name: &str| -> String {
        argv.get(index)
            .cloned()
            .unwrap_or_else(|| fail(&format!("{} needs a {name}", argv[0])))
    };
    let state = State::current();
    match argv[0].as_str() {
        "_sessions" => {
            let mut opts = parse_args(&argv[1..]);
            opts.all |= state.all;
            if state.fuzzy {
                // fzf filters the titles itself.
                opts.query.clear();
            }
            style::set(style::resolve(opts.color.as_deref().or(Some("always"))));
            let cwd = opts
                .target
                .clone()
                .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
            let (sessions, all) = find_sessions(&opts, &cwd);
            emit_rows(&session_rows(&sessions, all, SessionLayout::Picker));
        }
        "_turns" => {
            let opts = parse_args(&argv[1..]);
            let path = opts.target.unwrap_or_else(|| fail("_turns needs a path"));
            style::set(style::resolve(opts.color.as_deref().or(Some("always"))));
            let query = if state.fuzzy { "" } else { &opts.query };
            let rows: Vec<String> = turn_rows(
                &path,
                opts.no_tools || state.dialogue,
                &scan::search_terms(query),
            )
            .into_iter()
            .rev()
            .map(|(_, key, fields)| format!("{key}\t{fields}"))
            .collect();
            emit_rows(&rows);
        }
        "_preview" => {
            let path = PathBuf::from(arg(1, "path"));
            let key = argv
                .iter()
                .position(|a| a == "--turn")
                .and_then(|i| argv.get(i + 1));
            style::set(style::resolve(colour_choice(argv)));
            emit(&render::readable(
                &path,
                key.map(String::as_str),
                state.details || argv.iter().any(|a| a == "--expanded"),
                state.dialogue || argv.iter().any(|a| a == "--no-tools"),
            ));
        }
        "_page" => {
            let path = PathBuf::from(arg(1, "path"));
            let render = output_style(false, None);
            let no_tools = state.dialogue || argv.iter().any(|a| a == "--no-tools");
            show(&render::full(&path, no_tools), render, true);
        }
        "_view" => {
            let path = PathBuf::from(arg(1, "path"));
            // The file holds markdown; nvim adds the colours.
            style::set(false);
            view_in_nvim(&render::full(&path, state.dialogue));
        }
        "_toggle" => {
            let mut next = state;
            let extra = match arg(1, "state").as_str() {
                "all" => {
                    next.all = !next.all;
                    ""
                }
                "dialogue" => {
                    next.dialogue = !next.dialogue;
                    ""
                }
                "details" => {
                    next.details = !next.details;
                    ""
                }
                "fuzzy" => {
                    next.fuzzy = !next.fuzzy;
                    // The exact search runs in this program at each change
                    // of the query. The fuzzy search runs in fzf.
                    if next.fuzzy {
                        "+unbind(change)+enable-search"
                    } else {
                        "+rebind(change)+disable-search"
                    }
                }
                other => fail(&format!("unknown state: {other}")),
            };
            emit(&format!("change-prompt({}){extra}", next.prompt()));
        }
        "_accept" => {
            // fzf writes these lines after the query and before the rows.
            let prompt = std::env::var("FZF_PROMPT").unwrap_or_default();
            emit(&format!(
                "print({})+print({})+accept",
                arg(1, "key"),
                prompt.trim_end()
            ));
        }
        other => fail(&format!("unknown command: {other}")),
    }
}

/// Print the session id of a transcript.
fn print_id(path: &Path) {
    let id = scan::summarize_file(path).map(|s| s.id).unwrap_or_default();
    emit(&format!("{id}\n"));
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.first().is_some_and(|a| a.starts_with('_')) {
        hidden_command(&argv);
        return;
    }
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "agent-log".to_string());

    let opts = parse_args(&argv);
    let cwd = std::env::current_dir().unwrap_or_default();
    let terms = scan::search_terms(&opts.query);

    // A directory argument limits the picker. A file argument opens that
    // file.
    let (target, cwd) = match &opts.target {
        Some(path) if path.is_dir() => (None, path.canonicalize().unwrap_or_else(|_| path.clone())),
        Some(path) => (Some(path.clone()), cwd),
        None => (None, cwd),
    };

    // The turn picker continues the state and the query of the conversation
    // picker.
    let mut state = State {
        all: opts.all,
        dialogue: opts.no_tools,
        ..State::default()
    };
    let mut query = opts.query.clone();

    let target = match target {
        Some(path) => path,
        None => {
            style::set(style::resolve(opts.color.as_deref().or(
                // Rows for fzf keep their colours; fzf reads them with --ansi.
                (!opts.list).then_some("always"),
            )));
            let (sessions, all) = find_sessions(&opts, &cwd);
            if opts.list {
                emit_rows(&session_rows(
                    &sessions,
                    all,
                    SessionLayout::List {
                        show_model: opts.show_model,
                    },
                ));
                return;
            }
            if sessions.is_empty() {
                eprintln!(
                    "agent-log: no conversations recorded for {} (try --all)",
                    cwd.display()
                );
                std::process::exit(1);
            }
            if opts.newest {
                PathBuf::from(&sessions[0].path)
            } else {
                state.all = all;
                let rows = session_rows(&sessions, all, SessionLayout::Picker);
                // fzf applies --nth to the output of the template. The tab
                // makes the title the last field, thus the fuzzy search
                // ignores the date, the agent and the model.
                let (fields, alternate_fields) = if opts.show_model {
                    ("{1}{5}\t{3}", "{1}\t{3}")
                } else {
                    ("{1}\t{3}", "{1}{5}\t{3}")
                };
                let commands = Commands {
                    rows: format!(
                        "{} _sessions {}{} --query {{q}}",
                        shell_quote(&exe),
                        shell_quote(&cwd.to_string_lossy()),
                        opts.agent
                            .map(|a| format!(" --agent {}", a.name()))
                            .unwrap_or_default()
                    ),
                    preview: format!("{} _preview {{2}} --color=always", shell_quote(&exe)),
                    conversation: "{2}".into(),
                };
                let Some(picked) = run_fzf(
                    &exe,
                    &rows,
                    Picker::Sessions,
                    state,
                    &opts.query,
                    &commands,
                    &[
                        format!("--with-nth={fields}"),
                        format!("--bind=alt-m:change-with-nth({alternate_fields}|{fields})"),
                        format!(
                            "--bind=alt-s:transform({} _toggle all)+reload({})",
                            shell_quote(&exe),
                            commands.rows
                        ),
                    ],
                ) else {
                    return;
                };
                let path = picked.rows[0]
                    .split('\t')
                    .nth(1)
                    .unwrap_or_default()
                    .to_string();
                if path.is_empty() {
                    return;
                }
                let path = PathBuf::from(path);
                match picked.action.as_str() {
                    "id" => return print_id(&path),
                    "all" => {
                        let render = output_style(opts.plain, opts.color.as_deref());
                        show(&render::full(&path, picked.state.dialogue), render, false);
                        return;
                    }
                    _ => {}
                }
                state = picked.state;
                // A fuzzy query matched the title, not the turns.
                query = if state.fuzzy {
                    String::new()
                } else {
                    picked.query
                };
                path
            }
        }
    };

    if !target.is_file() {
        fail(&format!("{} not found", target.display()));
    }

    if let Some(n) = opts.turn {
        let rows = turn_rows(&target, opts.no_tools, &[]);
        let total = rows.len() as i64;
        let index = if n < 0 { total + n } else { n - 1 };
        if index < 0 || index >= total {
            fail(&format!("--turn {n} out of range (have {total} turns)"));
        }
        let render = output_style(opts.plain, opts.color.as_deref());
        let key = &rows[index as usize].1;
        show(
            &format!("{}{}", render::header(&target), render::turn(&target, key)),
            render,
            false,
        );
        return;
    }

    if opts.full || opts.newest {
        let render = output_style(opts.plain, opts.color.as_deref());
        show(&render::full(&target, opts.no_tools), render, render);
        return;
    }

    if opts.list {
        style::set(style::resolve(opts.color.as_deref()));
        let rows: Vec<String> = turn_rows(&target, opts.no_tools, &terms)
            .into_iter()
            .rev()
            .map(|(position, _, fields)| format!("{position}\t{fields}"))
            .collect();
        emit_rows(&rows);
        return;
    }

    style::set(style::resolve(opts.color.as_deref().or(Some("always"))));
    state.turns = true;
    let mut rows = turn_rows(&target, state.dialogue, &scan::search_terms(&query));
    if rows.is_empty() && !query.is_empty() {
        // The words of a conversation search can be in different turns.
        query.clear();
        rows = turn_rows(&target, state.dialogue, &[]);
    }
    if rows.is_empty() {
        eprintln!("agent-log: {} has no turns", target.display());
        std::process::exit(1);
    }
    let display: Vec<String> = rows
        .iter()
        .rev()
        .map(|(_, key, fields)| format!("{key}\t{fields}"))
        .collect();
    let path = shell_quote(&target.to_string_lossy());
    let commands = Commands {
        rows: format!("{} _turns {path} --query {{q}}", shell_quote(&exe)),
        preview: format!(
            "{} _preview {path} --turn {{1}} --color=always",
            shell_quote(&exe)
        ),
        conversation: path,
    };
    let Some(picked) = run_fzf(
        &exe,
        &display,
        Picker::Turns,
        state,
        &query,
        &commands,
        &[
            // Hide the internal record key, not the searchable body.
            "--with-nth=2,3,4".into(),
            "--multi".into(),
            // Select a row above the cursor. This is the opposite of tab.
            "--bind=shift-tab:toggle+up".into(),
        ],
    ) else {
        return;
    };

    let render = output_style(opts.plain, opts.color.as_deref());
    match picked.action.as_str() {
        "id" => return print_id(&target),
        "all" => return show(&render::full(&target, picked.state.dialogue), render, false),
        _ => {}
    }
    let mut keys: Vec<usize> = picked
        .rows
        .iter()
        .filter_map(|line| line.split('\t').next()?.trim().parse().ok())
        .collect();
    keys.sort_unstable();
    keys.dedup();
    let mut body = render::header(&target);
    for (index, key) in keys.iter().enumerate() {
        if index > 0 {
            body.push_str(&format!("\n{}\n\n", style::rule()));
        }
        body.push_str(&render::turn(&target, &key.to_string()));
    }
    show(&body, render, false);
}
