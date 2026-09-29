//! Bounded, uncached JSONL reads. Most records borrow the read buffer directly;
//! only a record straddling buffers needs copying. Never mmap a live log: an
//! agent can truncate it while we read it.

use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

/// Call `visit` for each physical line; false stops reading immediately.
/// `scratch` is reusable I/O workspace, not retained transcript results.
pub fn lines(
    path: &Path,
    scratch: &mut Vec<u8>,
    mut visit: impl FnMut(&str) -> bool,
) -> Option<()> {
    let mut reader = BufReader::with_capacity(128 * 1024, File::open(path).ok()?);
    scratch.clear();
    loop {
        let bytes = reader.fill_buf().ok()?;
        if bytes.is_empty() {
            break;
        }
        let mut start = 0;
        while let Some(length) = memchr::memchr(b'\n', &bytes[start..]) {
            let end = start + length;
            let keep_reading = if scratch.is_empty() {
                visit(simdutf8::basic::from_utf8(&bytes[start..end]).ok()?)
            } else {
                scratch.extend_from_slice(&bytes[start..end]);
                let keep = visit(simdutf8::basic::from_utf8(scratch).ok()?);
                scratch.clear();
                keep
            };
            if !keep_reading {
                return Some(());
            }
            start = end + 1;
        }
        scratch.extend_from_slice(&bytes[start..]);
        let consumed = bytes.len();
        reader.consume(consumed);
    }
    if !scratch.is_empty() {
        visit(simdutf8::basic::from_utf8(scratch).ok()?);
        scratch.clear();
    }
    Some(())
}
