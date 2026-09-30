//! agent-log shows the conversations of Claude Code, pi and Codex in one
//! picker.
//!
//! This program reads the files, summarizes them and shows the text. fzf makes
//! the selection. The key commands of fzf start this program again with the
//! hidden subcommands that have a name with the prefix `_`.

use std::io::Write;
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

PATH may be a transcript (any of the supported formats, detected by content)
or a directory, which scopes the picker to conversations recorded in it.
With no PATH, picks among conversations whose cwd is the current directory.

Options:
  --all             Every project, not just the current directory
  --agent <name>    Only claude, pi or codex
  --newest          Skip the picker; take the most recent match
  --full            Print the whole conversation and exit
  --turn <n>        Print the nth turn and exit (negative counts from the end)
  --list            Print picker rows to stdout instead of running fzf
  --query <text>    Filter sessions by full text (space-separated AND terms)
  --no-tools        With --full, drop tool calls and results (dialogue only)
  --pretty          Render through glow/bat when stdout is a terminal
  --color <when>    always, never or auto (default: auto; NO_COLOR is honoured)
  -h, --help        Show this help

Typing in either picker searches the whole conversation — prompts, replies,
thinking and tool traffic — by exact substring, case-insensitive; a space
separates AND terms.

Results and marked turns are always newest first, including while searching.
--turn numbers still count from the beginning; --full reads chronologically.
No caches or indexes: every request reads the original transcripts.
";

const COMMON_HELP: &str = "pgup/pgdn         scroll preview by a page
shift-up/down     scroll preview by a line (also alt-up/down)
mouse wheel       scroll the pane under the pointer
alt-p             show/hide preview
alt-e             toggle context, thinking and tool details
esc               close picker · f1 hide help";
const SESSION_HELP: &str = "enter             open conversation
alt-i             print session id and exit
alt-a             whole conversation in pager
alt-v             open in nvim
ctrl-a            search all projects";
const TURN_HELP: &str = "enter             print selected turns
tab / shift-tab   mark/unmark turns
alt-enter         print focused turn via glow/bat
alt-a / alt-v     whole conversation in pager / nvim
ctrl-t            toggle tools and dialogue
alt-g / alt-G     earliest / latest turn";
const EXPANDED_LABEL: &str = "Details expanded";

fn usage() -> String {
    format!("{USAGE}\nSession picker:\n{SESSION_HELP}\n\nTurn picker:\n{TURN_HELP}\n\nBoth pickers:\n{COMMON_HELP}\n")
}

#[derive(Default)]
struct Options {
    all: bool,
    agent: Option<Agent>,
    newest: bool,
    full: bool,
    list: bool,
    pretty: bool,
    no_tools: bool,
    turn: Option<i64>,
    color: Option<String>,
    query: String,
    target: Option<PathBuf>,
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
            "--pretty" => opts.pretty = true,
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

fn collect_sessions(opts: &Options, cwd: &Path) -> Vec<model::Session> {
    let mut paths = Vec::new();
    // A scoped run is the usual command, and it removes most of the sessions
    // that a full read collects. Thus ignore the directories that cannot
    // agree, and read only the sessions of this project.
    let candidates = (!opts.all).then(|| scan::project_dir_candidates(cwd));
    for (agent, root) in scan::roots(&home()) {
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
        (!opts.all).then_some(here.as_ref()),
    )
}

/// Compact session rows. Full text is searched on demand by `_sessions`;
/// feeding entire transcripts to fzf made even an empty query expensive.
fn session_rows(sessions: &[model::Session], show_project: bool) -> Vec<String> {
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
            // Keep the old column positions for paths and IDs. Full search
            // text no longer travels through the reserved third column.
            format!(
                "{}  {} {}{}\t{}\t{}\t{}",
                style::dim(&scan::format_when(s.last_activity)),
                style::dim(&format!("{:<6}", s.agent)),
                project,
                model::truncate(&s.title, 110),
                s.path,
                "",
                s.id
            )
        })
        .collect()
}

fn turn_rows(path: &Path, no_tools: bool) -> Vec<(String, String)> {
    scan::turns(path, no_tools)
        .unwrap_or_else(|| fail(&format!("cannot read transcript {}", path.display())))
        .into_iter()
        .map(|t| {
            // Keep all text searchable. The UI clips rows instead of hiding
            // body fields with --with-nth (which would also hide matches).
            (
                t.key.clone(),
                format!(
                    "{}\t{}\t{}\t{}\t{}",
                    t.key,
                    style::dim(&format!("{:<14}", model::truncate(&t.kind, 14))),
                    style::dim(&format!("{:>8}", t.time)),
                    t.text,
                    ""
                ),
            )
        })
        .collect()
}

/// Show markdown with glow, or with bat, or without changes. Use a program
/// only if the output goes to a terminal. Such a program changes the line
/// breaks, and this makes a file incorrect.
fn pretty(text: &str, enabled: bool) {
    use std::io::IsTerminal;
    if !enabled || !std::io::stdout().is_terminal() {
        emit(text);
        return;
    }
    for (program, args) in [
        ("glow", vec!["-"]),
        (
            "bat",
            vec!["--language=markdown", "--style=plain", "--paging=never"],
        ),
    ] {
        if pipe_through(program, &args, text) {
            return;
        }
    }
    emit(text);
}

/// Page the same rendered text as the preview, without reformatting it.
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

enum Picker {
    Sessions,
    Turns,
}

fn run_fzf(
    exe: &str,
    rows: &[String],
    picker: Picker,
    preview: &str,
    args: &[String],
) -> Option<String> {
    let (help, footer, hidden) = match picker {
        Picker::Sessions => (
            SESSION_HELP,
            "enter open · alt-p preview · f1 help",
            ",hidden",
        ),
        Picker::Turns => (TURN_HELP, "enter print · alt-e details · f1 help", ""),
    };
    let mut child = Command::new("fzf")
        .args([
            "--style=minimal",
            "--reverse",
            "--ansi",
            "--delimiter=\t",
            "--no-sort",
            "--exact",
            "-i",
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
            "--ghost=Search full text · newest first",
            "--header-first",
            "--footer-border=none",
            "--bind=start:hide-header+first",
            "--bind=f1:toggle-header",
            "--bind=alt-p:toggle-preview",
            // Paging the list changes the focused row and restarts its
            // preview. These bindings scroll the existing preview instead.
            "--bind=pgup:preview-page-up,pgdn:preview-page-down",
            "--bind=shift-up:preview-up,shift-down:preview-down",
            "--bind=alt-up:preview-up,alt-down:preview-down",
            "--bind=preview-scroll-up:preview-up,preview-scroll-down:preview-down",
            "--preview-label=",
            "--wrap-sign=",
        ])
        .arg(format!("--header={help}\n{COMMON_HELP}"))
        .arg(format!("--footer={footer}"))
        .arg(format!("--preview={preview}"))
        .arg(format!(
            "--preview-window=right,55%,wrap,border-left{hidden},<60(down,50%,border-top{hidden})"
        ))
        .arg(format!(
            "--bind=alt-e:transform({} _details)",
            shell_quote(exe)
        ))
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
    let picked = String::from_utf8_lossy(&output.stdout)
        .trim_end()
        .to_string();
    (!picked.is_empty()).then_some(picked)
}

fn dialogue_only() -> bool {
    std::env::var("FZF_PROMPT").is_ok_and(|p| p == turn_prompt(true))
}

fn details_expanded() -> bool {
    std::env::var("FZF_PREVIEW_LABEL").is_ok_and(|label| label == EXPANDED_LABEL)
}

fn turn_prompt(no_tools: bool) -> &'static str {
    if no_tools {
        "dialogue> "
    } else {
        "turns> "
    }
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "agent-log".to_string());

    // The hidden subcommands for the preview and the key commands of fzf.
    match argv.first().map(String::as_str) {
        Some("_turns") => {
            style::set(style::resolve(colour_choice(&argv).or(Some("always"))));
            let path = PathBuf::from(argv.get(1).unwrap_or_else(|| fail("_turns needs a path")));
            let no_tools = argv.iter().any(|a| a == "--no-tools");
            let rows: Vec<String> = turn_rows(&path, no_tools)
                .into_iter()
                .rev()
                .map(|(_, row)| row)
                .collect();
            emit_rows(&rows);
            return;
        }
        Some("_show") => {
            let key = argv.get(1).unwrap_or_else(|| fail("_show needs a key"));
            let path = PathBuf::from(argv.get(2).unwrap_or_else(|| fail("_show needs a path")));
            let want_pretty = argv.iter().any(|a| a == "--pretty");
            // glow and bat add their own colours.
            style::set(!want_pretty && style::resolve(colour_choice(&argv)));
            pretty(&render::header_and_turn(&path, key), want_pretty);
            return;
        }
        Some("_view") => {
            let path = PathBuf::from(argv.get(1).unwrap_or_else(|| fail("_view needs a path")));
            // The file holds markdown; nvim adds the colours.
            style::set(false);
            view_in_nvim(&render::full(&path, false));
            return;
        }
        Some(command @ ("_preview" | "_page")) => {
            let paged = command == "_page";
            let path = PathBuf::from(
                argv.get(1)
                    .unwrap_or_else(|| fail(&format!("{command} needs a path"))),
            );
            let key = argv
                .iter()
                .position(|a| a == "--turn")
                .and_then(|i| argv.get(i + 1));
            style::set(style::resolve(colour_choice(&argv)));
            let body = render::readable(
                &path,
                key.map(String::as_str),
                paged || details_expanded() || argv.iter().any(|a| a == "--expanded"),
                dialogue_only() || argv.iter().any(|a| a == "--no-tools"),
            );
            if paged {
                page(&body);
            } else {
                emit(&body);
            }
            return;
        }
        Some("_details") => {
            // fzf holds the UI state; no state files or transcript copies.
            let label = if details_expanded() {
                ""
            } else {
                EXPANDED_LABEL
            };
            emit(&format!(
                "change-preview-label({label})+refresh-preview+show-preview"
            ));
            return;
        }
        Some("_tools") => {
            let path = argv.get(1).unwrap_or_else(|| fail("_tools needs a path"));
            let no_tools = !dialogue_only();
            emit(&format!(
                "reload({} _turns {}{})+change-prompt({})+first",
                shell_quote(&exe),
                shell_quote(path),
                if no_tools { " --no-tools" } else { "" },
                turn_prompt(no_tools)
            ));
            return;
        }
        Some("_sessions") => {
            let mut opts = parse_args(&argv[1..]);
            opts.all |= std::env::var("FZF_PROMPT").is_ok_and(|p| p.starts_with("all>"));
            style::set(style::resolve(opts.color.as_deref().or(Some("always"))));
            let cwd = opts
                .target
                .clone()
                .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
            let sessions = collect_sessions(&opts, &cwd);
            emit_rows(&session_rows(&sessions, opts.all));
            return;
        }
        _ => {}
    }

    let opts = parse_args(&argv);
    style::set(!opts.pretty && style::resolve(opts.color.as_deref()));
    let cwd = std::env::current_dir().unwrap_or_default();

    // A directory argument limits the picker. A file argument opens that
    // file.
    let (target, cwd) = match &opts.target {
        Some(path) if path.is_dir() => (None, path.canonicalize().unwrap_or_else(|_| path.clone())),
        Some(path) => (Some(path.clone()), cwd),
        None => (None, cwd),
    };

    let target = match target {
        Some(path) => path,
        None => {
            let sessions = collect_sessions(&opts, &cwd);
            if opts.list {
                emit_rows(&session_rows(&sessions, opts.all));
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
                let rows = session_rows(&sessions, opts.all);
                let reload = format!(
                    "{} _sessions {}{}{} --query {{q}}",
                    shell_quote(&exe),
                    shell_quote(&cwd.to_string_lossy()),
                    if opts.all { " --all" } else { "" },
                    opts.agent
                        .map(|a| format!(" --agent {}", a.name()))
                        .unwrap_or_default()
                );
                let picked = run_fzf(
                    &exe,
                    &rows,
                    Picker::Sessions,
                    &format!("{} _preview {{2}} --color=always", shell_quote(&exe)),
                    &[
                        if opts.all {
                            "--prompt=all> ".into()
                        } else {
                            "--prompt=conversation> ".into()
                        },
                        "--with-nth=1".into(),
                        format!("--query={}", opts.query),
                        "--disabled".into(),
                        format!("--bind=change:reload({reload})"),
                        format!("--bind=alt-a:execute({} _page {{2}})", shell_quote(&exe)),
                        format!("--bind=alt-v:execute({} _view {{2}})", shell_quote(&exe)),
                        format!("--bind=ctrl-a:change-prompt(all> )+reload({reload} --all)"),
                        // alt-i selects a row, and fzf writes the name of the
                        // key on the first line. Thus this program can write
                        // the id and stop.
                        "--expect=alt-i".into(),
                    ],
                );
                match picked {
                    Some(out) => {
                        let mut lines = out.lines();
                        let key = lines.next().unwrap_or("");
                        let row = lines.next().unwrap_or("");
                        let path = row.split('\t').nth(1).unwrap_or_default().to_string();
                        if path.is_empty() {
                            return;
                        }
                        if key == "alt-i" {
                            emit(&format!("{}\n", row.split('\t').nth(3).unwrap_or(&path)));
                            return;
                        }
                        PathBuf::from(path)
                    }
                    None => return,
                }
            }
        }
    };

    if !target.is_file() {
        fail(&format!("{} not found", target.display()));
    }

    if opts.full {
        pretty(&render::full(&target, opts.no_tools), opts.pretty);
        return;
    }

    let rows = turn_rows(&target, opts.no_tools);
    if rows.is_empty() {
        eprintln!("agent-log: {} has no turns", target.display());
        std::process::exit(1);
    }

    let mut keys: Vec<String> = if let Some(n) = opts.turn {
        let total = rows.len() as i64;
        let index = if n < 0 { total + n } else { n - 1 };
        if index < 0 || index >= total {
            fail(&format!("--turn {n} out of range (have {total} turns)"));
        }
        vec![rows[index as usize].0.clone()]
    } else if opts.list {
        emit_rows(
            &rows
                .iter()
                .rev()
                .map(|(_, row)| row.clone())
                .collect::<Vec<_>>(),
        );
        return;
    } else {
        let display: Vec<String> = rows.iter().rev().map(|(_, row)| row.clone()).collect();
        let path = target.to_string_lossy().to_string();
        let picked = run_fzf(
            &exe,
            &display,
            Picker::Turns,
            &format!(
                "{} _preview {} --turn {{1}} --color=always",
                shell_quote(&exe),
                shell_quote(&path)
            ),
            &[
                format!("--prompt={}", turn_prompt(opts.no_tools)),
                // Hide the internal record key, not the searchable body.
                "--with-nth=2,3,4,5".into(),
                "--multi".into(),
                // Select a row above the cursor. This is the opposite of tab.
                "--bind=shift-tab:toggle+up".into(),
                format!(
                    "--bind=alt-a:execute({} _page {})",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                format!(
                    "--bind=alt-v:execute({} _view {})",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                format!(
                    "--bind=ctrl-t:transform({} _tools {})",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                format!(
                    "--bind=alt-enter:become({} _show {{1}} {} --pretty)",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                "--bind=alt-g:last,alt-G:first".into(),
            ],
        );
        match picked {
            Some(text) => text
                .lines()
                .filter_map(|line| line.split('\t').next().map(|k| k.trim().to_string()))
                .collect(),
            None => return,
        }
    };

    // Selection order never overrides newest-first ordering.
    keys.sort_by_key(|key| std::cmp::Reverse(key.parse::<usize>().unwrap_or(0)));
    keys.dedup();
    let mut body = String::new();
    for (index, key) in keys.iter().enumerate() {
        if index == 0 {
            body.push_str(&render::header(&target));
        } else {
            body.push_str(&format!("\n{}\n\n", style::rule()));
        }
        body.push_str(&render::turn(&target, key));
    }
    pretty(&body, opts.pretty);
}
