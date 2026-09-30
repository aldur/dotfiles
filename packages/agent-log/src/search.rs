//! Full-text matching without storing a corpus. The raw-text prefilter is
//! conservative: text that could match only after decoding gets decoded.

use aho_corasick::AhoCorasick;
use serde_json::Value;

use crate::adapters::{self, Agent};
use crate::model::Session;

pub struct Query<'a> {
    pub terms: &'a [String],
    raw: Option<AhoCorasick>,
}

impl<'a> Query<'a> {
    pub fn new(terms: &'a [String]) -> Self {
        let simple = !terms.is_empty()
            && terms.iter().all(|t| {
                t.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
            });
        let raw = simple
            .then(|| {
                AhoCorasick::builder()
                    .ascii_case_insensitive(true)
                    .build(terms)
                    .ok()
            })
            .flatten();
        Self { terms, raw }
    }

    fn could_match(&self, line: &str) -> bool {
        let Some(raw) = &self.raw else {
            return true;
        };
        // JSON Unicode escapes can spell any character. \b and \f are
        // stripped by flatten(), potentially joining the two sides of a word.
        // These are the only non-ASCII scalars whose lowercase introduces an
        // ASCII character. The exhaustive test below guards Unicode updates.
        line.contains('\u{212a}')
            || line.contains('\u{0130}')
            || memchr::memmem::find(line.as_bytes(), b"\\u").is_some()
            || memchr::memmem::find(line.as_bytes(), b"\\b").is_some()
            || memchr::memmem::find(line.as_bytes(), b"\\f").is_some()
            || raw.is_match(line)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn unicode_lowercase_prefilter_is_complete() {
        let bridges: Vec<_> = (128..=0x10ffff)
            .filter_map(char::from_u32)
            .filter(|c| c.to_lowercase().any(|lower| lower.is_ascii()))
            .collect();
        assert_eq!(bridges, vec!['\u{0130}', '\u{212a}']);
    }
}

pub struct Matches<'a, 'q> {
    query: &'q Query<'a>,
    found: Vec<bool>,
    remaining: usize,
}

impl<'a, 'q> Matches<'a, 'q> {
    pub fn new(query: &'q Query<'a>) -> Self {
        Self {
            query,
            found: vec![false; query.terms.len()],
            remaining: query.terms.len(),
        }
    }

    pub fn text(&mut self, text: &str) {
        if self.remaining == 0 {
            return;
        }
        let lower = text.to_lowercase();
        for (term, found) in self.query.terms.iter().zip(&mut self.found) {
            if !*found && lower.contains(term) {
                *found = true;
                self.remaining -= 1;
            }
        }
    }

    pub fn record(&mut self, agent: Agent, line: &str) {
        if self.remaining == 0 || !self.query.could_match(line) {
            return;
        }
        let Ok(record) = sonic_rs::from_str::<Value>(line) else {
            return;
        };
        self.text(&adapters::text(agent, &record));
    }

    pub fn finish(mut self, session: &Session) -> bool {
        self.text(&format!(
            "{} {} {} {}",
            crate::scan::format_when(session.last_activity),
            session.agent,
            session.cwd,
            session.title
        ));
        self.remaining == 0
    }
}
