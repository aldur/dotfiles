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
mod model;
mod render;
mod style;
mod scan;

use adapters::Agent;

const USAGE: &str = "\
agent-log — browse Claude Code, pi and Codex conversations

Usage: agent-log [options] [PATH]

PATH may be a transcript (any of the supported formats, detected by content)
or a directory, which scopes the picker to conversations recorded in it.
With no PATH, picks among conversations whose cwd is the current directory.

Options:
  --all             Every project, not just the current directory
  --agent <name>    Only claude, pi, codex or wire
  --newest          Skip the picker; take the most recent match
  --full            Print the whole conversation and exit
  --turn <n>        Print the nth turn and exit (negative counts from the end)
  --list            Print picker rows to stdout instead of running fzf
  --no-tools        With --full, drop tool calls and results (dialogue only)
  --pretty          Render through glow/bat when stdout is a terminal
  --color <when>    always, never or auto (default: auto; NO_COLOR is honoured)
  -h, --help        Show this help

Typing in either picker searches the whole conversation — prompts, replies,
thinking and tool traffic — by exact substring, case-insensitive; a space
separates AND terms.

In the session picker:
  enter    open the conversation in the turn picker
  alt-i    print the session id and exit (feeds `claude --resume <id>`)
  alt-a    read the whole conversation in a pager
  alt-v    open it in nvim
  ctrl-a   widen to every project
  alt-p    toggle the preview

In the turn picker (rows are timestamped; typing searches the whole text of
every turn, not just the visible snippet):
  enter      print the selected turn(s)
  tab        mark/unmark and move down (multi-select)
  shift-tab  mark/unmark and move up (extend a range)
  alt-enter  print the focused turn rendered via glow/bat
  alt-a      whole conversation in a pager
  alt-v      open it in nvim
  ctrl-o     toggle ordering (newest-first <-> oldest-first)
  ctrl-t     toggle tool calls and results (dialogue only), which alt-a follows
  alt-g      jump to the earliest turn; alt-G to the latest
  alt-p      toggle the preview

Marked turns print together in chronological order, whatever order they were
marked in.
";

/// The keys that each picker shows in its footer. These are constants,
/// because a footer that does not agree with the key commands is incorrect.
/// The tests examine these values.
const SESSION_FOOTER: &str = "enter open   alt-i id only   alt-a whole convo   \
alt-v nvim   ctrl-a all projects   alt-p preview";
const TURN_FOOTER: &str = "enter print   tab/shift-tab mark +/-   alt-enter pretty   \
alt-a whole convo   alt-v nvim   ctrl-o order   ctrl-t tools   alt-g/G earliest/latest   alt-p preview";

/// Make each word that is not the name of a key less bright. Thus the names
/// of the keys are easy to find.
fn footer(text: &str) -> String {
    let mut out = String::from("--footer=");
    for (index, word) in text.split_whitespace().enumerate() {
        if index > 0 {
            out.push(' ');
        }
        let is_key = word.contains('-') && !word.contains("convo") || word == "enter" || word == "tab";
        if is_key {
            out.push_str(word);
        } else {
            out.push_str(&style::dim(word));
        }
    }
    out
}

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

fn fail(message: &str) -> ! {
    eprintln!("agent-log: {message}");
    std::process::exit(2);
}

fn parse_args(args: &[String]) -> Options {
    let mut opts = Options {
        all: false,
        agent: None,
        newest: false,
        full: false,
        list: false,
        pretty: false,
        no_tools: false,
        turn: None,
        color: None,
        target: None,
    };
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
                emit(USAGE);
                std::process::exit(0);
            }
            "--all" => opts.all = true,
            "--newest" => opts.newest = true,
            "--full" => opts.full = true,
            "--list" => opts.list = true,
            "--pretty" => opts.pretty = true,
            "--no-tools" => opts.no_tools = true,
            "--color" => opts.color = Some(next()),
            other if other.starts_with("--color=") => {
                opts.color = Some(other.trim_start_matches("--color=").to_string())
            }
            "--agent" => {
                let name = next();
                opts.agent =
                    Some(Agent::parse(&name).unwrap_or_else(|| fail(&format!("unknown agent: {name}"))));
            }
            "--turn" => {
                let value = next();
                opts.turn = Some(
                    value
                        .parse()
                        .unwrap_or_else(|_| fail(&format!("--turn wants an integer, got {value}"))),
                );
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
    let mut sessions = scan::summarize_all(&paths, opts.agent);
    if !opts.all {
        let here = cwd.to_string_lossy().to_string();
        // A proxy transcript records no working directory. Thus it is only
        // available with `--all`. Do not connect it to the current
        // directory.
        sessions.retain(|s| s.cwd == here);
    }
    for session in &mut sessions {
        session.when = scan::format_when(session.last_activity);
    }
    sessions
}

/// One row for each session. fzf shows the fields 1 and 3, and searches both
/// of them. fzf does not search a field that `--with-nth` hides.
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
            // The fields are the display text, the path, the search text and
            // the id. The key commands use the fields 2 and 4.
            format!(
                "{}  {} {}{}\t{}\t{}\t{}",
                style::cyan(&s.when),
                style::tool(&format!("{:<6}", s.agent)),
                project,
                model::truncate(&s.title, 110),
                s.path,
                style::dim(&s.corpus),
                s.id
            )
        })
        .collect()
}

fn turn_rows(path: &Path, no_tools: bool) -> Vec<(String, String)> {
    let Some((records, _)) = scan::parse_file(path) else {
        fail(&format!("cannot read {}", path.display()));
    };
    let Some(agent) = adapters::detect(&records) else {
        fail(&format!("{}: unrecognised transcript format", path.display()));
    };
    adapters::turns(agent, &records, no_tools)
        .into_iter()
        .map(|t| {
            let colour: fn(&str) -> String = match t.kind.as_str() {
                k if k.contains("user") => style::user,
                k if k.contains("thinking") => style::thinking,
                k if k.contains("tool_result") || k.contains("tool result") => style::result,
                k if k.contains("tool") || k.contains("flight") => style::tool,
                _ => style::assistant,
            };
            (
                t.key.clone(),
                format!(
                    "{}\t{}\t{}\t{}\t{}",
                    t.key,
                    colour(&format!("{:<14}", model::truncate(&t.kind, 14))),
                    style::dim(&format!("{:>8}", t.time)),
                    t.label,
                    style::dim(&t.text)
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
        ("bat", vec!["--language=markdown", "--style=plain", "--paging=never"]),
    ] {
        if pipe_through(program, &args, text) {
            return;
        }
    }
    emit(text);
}

/// Show markdown in a pager. Use the first program that is available.
///
/// These programs are not build dependencies. A dependency adds tens of
/// megabytes to the closure, and most machines already have such a program.
fn page(text: &str) {
    if let Ok(pager) = std::env::var("PAGER") {
        if !pager.trim().is_empty() && pipe_through("sh", &["-c", &format!("{pager}")], text) {
            return;
        }
    }
    for (program, args) in [
        ("bat", vec!["--language=markdown", "--style=plain", "--paging=always"]),
        ("less", vec!["-R"]),
    ] {
        if pipe_through(program, &args, text) {
            return;
        }
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
    let Ok(mut child) = Command::new(program).args(args).stdin(Stdio::piped()).spawn() else {
        return false;
    };
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let _ = child.wait();
    true
}

fn run_fzf(rows: &[String], args: &[String]) -> Option<String> {
    let mut child = Command::new("fzf")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| fail(&format!("cannot run fzf: {e}")));
    {
        let stdin = child.stdin.as_mut().expect("piped");
        for row in rows {
            let _ = writeln!(stdin, "{row}");
        }
    }
    let output = child.wait_with_output().ok()?;
    if !output.status.success() {
        return None;
    }
    let picked = String::from_utf8_lossy(&output.stdout).trim_end().to_string();
    (!picked.is_empty()).then_some(picked)
}

/// The state of the turn picker.
///
/// A key command can read only the prompt. Thus the two options write
/// themselves into the prompt, and each option keeps the other one.
struct Picker {
    oldest_first: bool,
    no_tools: bool,
}

impl Picker {
    /// A person reads a conversation from the oldest turn to the newest turn.
    /// Thus the picker opens in that sequence. The cursor starts at the newest
    /// turn, and the older turns stay above it.
    fn default_view() -> Picker {
        Picker { oldest_first: true, no_tools: false }
    }

    fn current() -> Picker {
        let prompt = std::env::var("FZF_PROMPT").unwrap_or_default();
        Picker {
            oldest_first: prompt.contains("oldest"),
            no_tools: prompt.contains("dialogue"),
        }
    }

    fn prompt(&self) -> String {
        format!(
            "turn {}{}> ",
            if self.oldest_first { "oldest-first" } else { "newest-first" },
            if self.no_tools { " · dialogue" } else { "" }
        )
    }

    /// fzf cannot change the sequence of the rows, and cannot remove rows
    /// that it did not receive. Thus each option reads the rows again.
    fn reload(&self, exe: &str, path: &str) -> String {
        format!(
            "reload({} _turns {} {}{})+change-prompt({})+first",
            shell_quote(exe),
            shell_quote(path),
            if self.oldest_first { "old" } else { "new" },
            if self.no_tools { " --no-tools" } else { "" },
            self.prompt()
        )
    }
}

/// The earliest turn and the latest turn are the two ends of the
/// conversation. The current sequence gives their position in the list.
fn jump_action(which: &str) -> &'static str {
    let oldest_first = Picker::current().oldest_first;
    match (which, oldest_first) {
        ("earliest", true) | ("latest", false) => "first",
        _ => "last",
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
            let reverse = argv.get(2).map(String::as_str) == Some("new");
            let no_tools = argv.iter().any(|a| a == "--no-tools");
            let rows: Vec<String> = turn_rows(&path, no_tools).into_iter().map(|(_, row)| row).collect();
            let rows: Vec<String> = if reverse { rows.into_iter().rev().collect() } else { rows };
            emit(&format!("{}\n", rows.join("\n")));
            return;
        }
        Some("_show") => {
            let key = argv.get(1).unwrap_or_else(|| fail("_show needs a key"));
            let path = PathBuf::from(argv.get(2).unwrap_or_else(|| fail("_show needs a path")));
            let want_pretty = argv.iter().any(|a| a == "--pretty");
            // glow and bat add their own colours.
            style::set(!want_pretty && style::resolve(colour_choice(&argv)));
            let body = render::header_and_turn(&path, key);
            pretty(&body, want_pretty);
            return;
        }
        Some("_page") => {
            style::set(style::resolve(colour_choice(&argv)));
            let path = PathBuf::from(argv.get(1).unwrap_or_else(|| fail("_page needs a path")));
            page(&render::full(&path, argv.iter().any(|a| a == "--no-tools")));
            return;
        }
        Some("_view") => {
            let path = PathBuf::from(argv.get(1).unwrap_or_else(|| fail("_view needs a path")));
            // The file holds markdown; nvim adds the colours.
            style::set(false);
            view_in_nvim(&render::full(&path, false));
            return;
        }
        Some("_full") => {
            let path = PathBuf::from(argv.get(1).unwrap_or_else(|| fail("_full needs a path")));
            let no_tools = argv.iter().any(|a| a == "--no-tools");
            style::set(style::resolve(colour_choice(&argv)));
            emit(&render::full(&path, no_tools));
            return;
        }
        Some("_footer") => {
            emit(&match argv.get(1).map(String::as_str) {
                Some("turn") => format!("{TURN_FOOTER}\n"),
                _ => format!("{SESSION_FOOTER}\n"),
            });
            return;
        }
        Some("_prompt") => {
            emit(&format!("{}\n", Picker::default_view().prompt()));
            return;
        }
        Some("_order") => {
            let path = argv.get(1).unwrap_or_else(|| fail("_order needs a path"));
            let mut next = Picker::current();
            next.oldest_first = !next.oldest_first;
            emit(&next.reload(&exe, path));
            return;
        }
        Some("_tools") => {
            let path = argv.get(1).unwrap_or_else(|| fail("_tools needs a path"));
            let mut next = Picker::current();
            next.no_tools = !next.no_tools;
            emit(&next.reload(&exe, path));
            return;
        }
        // alt-a must obey the current view. Only a transform can read the
        // prompt. Thus this subcommand writes the execute action.
        Some("_page_action") => {
            let path = argv.get(1).unwrap_or_else(|| fail("_page_action needs a path"));
            let flag = if Picker::current().no_tools { " --no-tools" } else { "" };
            emit(&format!(
                "execute({} _page {}{flag})",
                shell_quote(&exe),
                shell_quote(path)
            ));
            return;
        }
        Some("_jump") => {
            let which = argv.get(1).map(String::as_str).unwrap_or("earliest");
            emit(jump_action(which));
            return;
        }
        Some("_sessions") => {
            let opts = parse_args(&argv[1..]);
            // Only a ctrl-a command uses this. fzf shows the colours.
            style::set(style::resolve(opts.color.as_deref().or(Some("always"))));
            let cwd = std::env::current_dir().unwrap_or_default();
            let sessions = collect_sessions(&opts, &cwd);
            emit(&format!("{}\n", session_rows(&sessions, opts.all).join("\n")));
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
        Some(path) if path.is_dir() => (None, path.clone()),
        Some(path) => (Some(path.clone()), cwd),
        None => (None, cwd),
    };

    let target = match target {
        Some(path) => path,
        None => {
            let sessions = collect_sessions(&opts, &cwd);
            if sessions.is_empty() {
                eprintln!(
                    "agent-log: no conversations recorded for {} (try --all)",
                    cwd.display()
                );
                std::process::exit(1);
            }
            if opts.list {
                emit(&format!("{}\n", session_rows(&sessions, opts.all).join("\n")));
                return;
            }
            if opts.newest {
                PathBuf::from(&sessions[0].path)
            } else {
                let rows = session_rows(&sessions, opts.all);
                let picked = run_fzf(
                    &rows,
                    &[
                        "--prompt=conversation> ".into(),
                        "--reverse".into(),
                        "--height=60%".into(),
                        "--ansi".into(),
                        "--delimiter=\t".into(),
                        "--with-nth=1,3".into(),
                        "--exact".into(),
                        "-i".into(),
                        format!("--preview={} _full {{2}} --color=always", shell_quote(&exe)),
                        "--preview-window=right,60%,wrap".into(),
                        "--bind=alt-p:toggle-preview".into(),
                        format!("--bind=alt-a:execute({} _page {{2}})", shell_quote(&exe)),
                        format!("--bind=alt-v:execute({} _view {{2}})", shell_quote(&exe)),
                        format!(
                            "--bind=ctrl-a:reload({} _sessions --all)+change-prompt(all> )",
                            shell_quote(&exe)
                        ),
                        // alt-i selects a row, and fzf writes the name of the
                        // key on the first line. Thus this program can write
                        // the id and stop.
                        "--expect=alt-i".into(),
                        "--wrap-sign=".into(),
                        footer(SESSION_FOOTER),
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

    let keys: Vec<String> = if let Some(n) = opts.turn {
        let total = rows.len() as i64;
        let index = if n < 0 { total + n } else { n - 1 };
        if index < 0 || index >= total {
            fail(&format!("--turn {n} out of range (have {total} turns)"));
        }
        vec![rows[index as usize].0.clone()]
    } else if opts.list {
        emit(&format!(
            "{}\n",
            rows.iter().map(|(_, row)| row.clone()).collect::<Vec<_>>().join("\n")
        ));
        return;
    } else {
        let view = Picker::default_view();
        let ordered: Vec<String> = rows.iter().map(|(_, row)| row.clone()).collect();
        let display: Vec<String> = if view.oldest_first {
            ordered
        } else {
            ordered.into_iter().rev().collect()
        };
        let path = target.to_string_lossy().to_string();
        let picked = run_fzf(
            &display,
            &[
                format!("--prompt={}", view.prompt()),
                "--reverse".into(),
                "--ansi".into(),
                "--delimiter=\t".into(),
                "--with-nth=1,2,3,4,5".into(),
                "--exact".into(),
                "-i".into(),
                "--multi".into(),
                format!(
                    "--preview={} _show {{1}} {} --color=always",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                "--preview-window=right,60%,wrap".into(),
                "--bind=alt-p:toggle-preview".into(),
                // The newest turn is at the bottom. Put the cursor there.
                "--bind=start:last".into(),
                // Select a row above the cursor. This is the opposite of tab.
                "--bind=shift-tab:toggle+up".into(),
                format!(
                    "--bind=alt-a:transform({} _page_action {})",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                format!("--bind=alt-v:execute({} _view {})", shell_quote(&exe), shell_quote(&path)),
                // Use a transform, because the new sequence depends on the
                // current sequence.
                format!("--bind=ctrl-o:transform({} _order {})", shell_quote(&exe), shell_quote(&path)),
                format!("--bind=ctrl-t:transform({} _tools {})", shell_quote(&exe), shell_quote(&path)),
                format!(
                    "--bind=alt-enter:become({} _show {{1}} {} --pretty)",
                    shell_quote(&exe),
                    shell_quote(&path)
                ),
                format!("--bind=alt-g:transform({} _jump earliest)", shell_quote(&exe)),
                format!("--bind=alt-G:transform({} _jump latest)", shell_quote(&exe)),
                "--wrap-sign=".into(),
                footer(TURN_FOOTER),
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

    // Show the selected turns in the sequence of the conversation, and not in
    // the sequence of the selection.
    let mut ordered: Vec<&(String, String)> =
        rows.iter().filter(|(key, _)| keys.contains(key)).collect();
    ordered.sort_by_key(|(key, _)| key.parse::<i64>().unwrap_or(0));
    let mut body = String::new();
    for (index, (key, _)) in ordered.iter().enumerate() {
        if index == 0 {
            body.push_str(&render::header(&target));
        } else {
            body.push_str(&format!("\n{}\n\n", style::rule()));
        }
        body.push_str(&render::turn(&target, key));
    }
    pretty(&body, opts.pretty);
}
