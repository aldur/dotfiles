//! The readers for the stores of the agents.
//!
//! No caches or indexes. Project only metadata for listings; read the full
//! content on demand for searches and rendering.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

use serde_json::Value;

use crate::adapters::{self, Agent};
use crate::model::{Session, Turn};

/// The directory of each agent. The program ignores a directory that does not
/// exist. Thus one agent alone causes no additional cost.
pub fn roots(home: &Path) -> Vec<(Agent, PathBuf)> {
    let pi_dir = std::env::var("PI_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home.join(".pi/agent"));
    vec![
        (Agent::Claude, home.join(".claude/projects")),
        (Agent::Pi, pi_dir.join("sessions")),
        (Agent::Codex, home.join(".codex/sessions")),
    ]
}

/// The possible names of the project directory for a working directory.
///
/// Claude and pi give a project directory the name of the working directory of
/// the conversation. Thus a scoped run can ignore other directories before it
/// reads a file. This is only a filter. The working directory in the file
/// makes the decision. If no directory agrees, the program reads all the
/// directories. Thus a change to the names decreases the speed, but the
/// results stay correct.
pub fn project_dir_candidates(cwd: &Path) -> Vec<String> {
    let path = cwd.to_string_lossy();
    let dashed: String = path
        .chars()
        .map(|c| if c == '/' || c == '.' { '-' } else { c })
        .collect();
    let trimmed = dashed.trim_start_matches('-');
    vec![dashed.clone(), format!("--{trimmed}--")]
}

/// All the `.jsonl` files below `root`. Claude and pi use one level of
/// directories. Codex uses three levels, for the year, the month and the day.
///
/// `only` gives the names of the project directories to read. It applies to
/// the first level below the root, because Claude and pi put the name of the
/// working directory there. Codex uses dates. Thus if no name agrees, the
/// program reads all the directories.
pub fn find_jsonl_filtered(root: &Path, only: Option<&[String]>, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    let mut children: Vec<PathBuf> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        match entry.file_type() {
            Ok(kind) if kind.is_dir() => children.push(path),
            Ok(_) if path.extension().is_some_and(|e| e == "jsonl") => out.push(path),
            _ => {}
        }
    }
    let matching: Vec<&PathBuf> = match only {
        Some(names) => children
            .iter()
            .filter(|c| {
                c.file_name()
                    .is_some_and(|n| names.iter().any(|want| want == &n.to_string_lossy()))
            })
            .collect(),
        None => children.iter().collect(),
    };
    // No directory agrees with this project. The names can be different, or
    // the store can use more levels. Read all of them, and show a result.
    let to_walk: Vec<&PathBuf> = if matching.is_empty() {
        children.iter().collect()
    } else {
        matching
    };
    for child in to_walk {
        find_jsonl_filtered(child, None, out);
    }
}

fn mtime(path: &Path) -> i64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub fn parse_file(path: &Path) -> Option<(Vec<Value>, i64)> {
    let text = fs::read_to_string(path).ok()?;
    Some((
        text.lines()
            .filter_map(|line| serde_json::from_str(line).ok())
            .collect(),
        mtime(path),
    ))
}

pub fn turn_record(path: &Path, key: usize) -> Option<(Agent, Value)> {
    let mut agent = None;
    let mut count = 0;
    let mut selected = None;
    crate::source::lines(path, &mut Vec::new(), |line| {
        if sonic_rs::from_str::<serde::de::IgnoredAny>(line).is_err() {
            return true;
        }
        count += 1;
        if agent.is_none() && count <= 50 {
            if let Ok(record) = serde_json::from_str::<Value>(line) {
                agent = adapters::detect(&[record]);
            }
        }
        if count == key {
            selected = serde_json::from_str(line).ok();
        }
        selected.is_none() || agent.is_none() && count < 50
    })?;
    Some((agent?, selected?))
}

pub fn search_terms(query: &str) -> Vec<String> {
    query.split_whitespace().map(str::to_lowercase).collect()
}

pub fn summarize_file(path: &Path, terms: &[String]) -> Option<Session> {
    crate::metadata::summarize(
        path,
        mtime(path),
        None,
        &mut Vec::new(),
        &crate::search::Query::new(terms),
    )
}

pub fn turns(path: &Path, no_tools: bool) -> Option<Vec<Turn>> {
    let (records, _) = parse_file(path)?;
    Some(adapters::turns(
        adapters::detect(&records)?,
        &records,
        no_tools,
    ))
}

/// Summarize many files together, with one thread for each core. Each thread
/// takes the next file from a shared counter. Thus one large file does not
/// stop the other threads.
pub fn summarize_all(
    paths: &[PathBuf],
    want: Option<Agent>,
    terms: &[String],
    cwd: Option<&str>,
) -> Vec<Session> {
    // Schedule large logs first: otherwise a large file assigned near the end
    // leaves one worker running after every other core has finished.
    let mut ordered: Vec<_> = paths.iter().collect();
    ordered.sort_by_cached_key(|path| {
        std::cmp::Reverse(fs::metadata(path).map(|m| m.len()).unwrap_or(0))
    });
    let paths = &ordered;
    let workers = thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        // More workers increased contention/tail latency in the full-history
        // benchmark. Leave room for the terminal and other active agents.
        .min(12)
        .min(paths.len().max(1));
    let next = AtomicUsize::new(0);
    let query = &crate::search::Query::new(terms);

    let mut sessions: Vec<Session> = thread::scope(|scope| {
        let handles: Vec<_> = (0..workers)
            .map(|_| {
                let next = &next;
                scope.spawn(move || {
                    let mut found = Vec::new();
                    let mut source = Vec::new();
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        let Some(path) = paths.get(index) else { break };
                        let Some(session) =
                            crate::metadata::summarize(path, mtime(path), cwd, &mut source, query)
                        else {
                            continue;
                        };
                        if want.is_some_and(|w| w.name() != session.agent) {
                            continue;
                        }
                        if cwd.is_some_and(|here| session.cwd != here) {
                            continue;
                        }
                        found.push(session);
                    }
                    found
                })
            })
            .collect();
        handles
            .into_iter()
            .filter_map(|h| h.join().ok())
            .flatten()
            .collect()
    });

    sessions.sort_by(|a, b| {
        b.last_activity
            .cmp(&a.last_activity)
            .then_with(|| a.path.cmp(&b.path))
    });
    sessions
}

/// Make a `YYYY-MM-DD HH:MM` text in UTC from a time in seconds. This is the
/// opposite of the parser in `adapters`. Both prevent a dependency on a date
/// library.
pub fn format_when(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (hour, minute) = (rem / 3_600, (rem % 3_600) / 60);

    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);

    format!("{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}")
}
