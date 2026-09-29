"""Regression tests for discovery, search, uncached reads and fzf."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


BINARY = str(Path(sys.argv.pop(1)).resolve())


class AgentLogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-log-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.project = self.root / "project ' with spaces"
        self.project.mkdir()
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.env = dict(os.environ, HOME=str(self.root), XDG_CACHE_HOME=str(self.root / "cache"),
                        PI_CODING_AGENT_DIR=str(self.root / ".pi/agent"), NO_COLOR="1",
                        XDG_RUNTIME_DIR=str(self.runtime))
        self.env.pop("FZF_PROMPT", None)
        self.env.pop("FZF_DEFAULT_OPTS", None)
        self.env.pop("FZF_DEFAULT_OPTS_FILE", None)
        self.files = []
        for name, hour in [("claude", 10), ("pi", 11), ("codex", 12)]:
            directory = {"claude": ".claude/projects/unusual", "pi": ".pi/agent/sessions/unusual",
                         "codex": ".codex/sessions/2026/08/10"}[name]
            path = self.root / directory / f"{name}.jsonl"
            path.parent.mkdir(parents=True)
            stamp = f"2026-08-10T{hour}:00:00.000Z"
            text = f"First {name} prompt"
            if name == "claude":
                records = [{"type": "user", "cwd": str(self.project), "timestamp": stamp,
                            "message": {"content": text}}]
            elif name == "pi":
                records = [{"type": "session", "id": name, "cwd": str(self.project), "timestamp": stamp},
                           {"type": "message", "timestamp": stamp, "message": {"role": "user", "content": text}}]
            else:
                records = [{"type": "session_meta", "timestamp": stamp, "payload": {"id": name, "cwd": str(self.project)}},
                           {"type": "response_item", "timestamp": stamp, "payload": {"type": "message", "role": "user", "content": text}},
                           {"type": "response_item", "timestamp": stamp, "payload": {"type": "reasoning", "summary": [{"text": "DeepThought Café"}]}},
                           {"type": "response_item", "timestamp": stamp, "payload": {"type": "function_call_output", "output": "ToolOnly needle buried in the middle"}},
                           {"type": "response_item", "timestamp": stamp, "payload": {"type": "message", "role": "assistant", "content": "FinalAnswer"}}]
            path.write_text("\n".join(map(json.dumps, records)) + "\n")
            self.files.append(path)

    def run_log(self, *args, env=None, cwd=None):
        return subprocess.run([BINARY, *map(str, args)], env=env or self.env, cwd=cwd or self.project,
                              text=True, capture_output=True, check=True).stdout

    def ids(self, *args, **kwargs):
        return [line.split("\t")[3] for line in self.run_log("--all", "--list", *args, **kwargs).splitlines() if line]

    def test_newest_first_and_complete_full_text_search(self):
        self.assertEqual(self.ids(), ["codex", "pi", "claude"])
        self.assertEqual(self.ids(), ["codex", "pi", "claude"])
        # AND terms can be in separate turns; middle/tool/thinking text matters.
        for query in ["toolonly", "deepthought CAFÉ", "needle finalanswer", "first finalanswer", "middle"]:
            self.assertEqual(self.ids("--query", query), ["codex"])
        self.assertEqual(self.ids("--query", "absent"), [])
        self.assertEqual(self.ids("--query", "first"), ["codex", "pi", "claude"])
        self.assertEqual(self.ids("--agent", "pi", "--query", "first"), ["pi"])
        self.assertLess(len(self.run_log("--all", "--list")), 2000)
        rows = self.run_log("--list", self.files[2]).splitlines()
        self.assertEqual([int(r.split("\t")[0]) for r in rows], [5, 4, 3, 2])
        self.assertIn("First codex", self.run_log("--turn", "1", self.files[2]))
        self.assertIn("FinalAnswer", self.run_log("--turn", "-1", self.files[2]))

    def test_reads_track_append_rewrite_truncate_replace_and_delete(self):
        path = self.files[0]
        original = path.read_text()
        self.ids()
        # Complete the last record after an interrupted write.
        appended = json.dumps({"type": "user", "timestamp": "2026-08-11T10:00:00.000Z",
                               "message": {"content": "AppendedNeedle"}})
        with path.open("a") as out:
            out.write(appended[:-5])
        self.assertEqual(self.ids("--query", "AppendedNeedle"), [])
        with path.open("a") as out:
            out.write(appended[-5:] + "\n")
        self.assertEqual(self.ids(), ["claude", "codex", "pi"])
        self.assertEqual(self.ids("--query", "AppendedNeedle"), ["claude"])
        self.assertIn("AppendedNeedle", self.run_log("_show", "2", path))
        self.assertIn("AppendedNeedle", self.run_log("--full", path))
        # Same length and restored mtime must still show the edited source.
        before = path.stat()
        path.write_text(path.read_text().replace("AppendedNeedle", "ReplacedNeedle"))
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        self.assertEqual(self.ids("--query", "AppendedNeedle"), [])
        self.assertEqual(self.ids("--query", "ReplacedNeedle"), ["claude"])
        self.assertIn("ReplacedNeedle", self.run_log("_show", "2", path))
        self.assertNotIn("AppendedNeedle", self.run_log("--full", path))
        path.write_text(original)
        self.assertEqual(self.ids("--query", "ReplacedNeedle"), [])
        replacement = path.with_suffix(".replacement")
        replacement.write_text(original.replace("First claude", "Other claude"))
        replacement.replace(path)
        self.assertEqual(self.ids("--query", "Other claude"), ["claude"])
        path.unlink()
        self.assertEqual(self.ids(), ["codex", "pi"])

    def test_no_persistent_cache_is_created_or_used(self):
        self.ids()
        self.assertFalse((self.root / "cache").exists())
        self.assertFalse((self.root / ".cache").exists())
        self.assertEqual(self.ids("--query", "toolonly"), ["codex"])
        self.run_log("--full", self.files[2])
        self.run_log("--list", self.files[2])
        self.run_log("_show", "5", self.files[2])
        self.assertFalse((self.root / "cache").exists())
        unavailable = self.root / "not-a-directory"
        unavailable.touch()
        env = dict(self.env, XDG_CACHE_HOME=str(unavailable))
        self.assertEqual(self.ids(env=env), ["codex", "pi", "claude"])
        self.assertIn("FinalAnswer", self.run_log("_show", "5", self.files[2], env=env))

    def test_picker_reads_sources_directly_and_creates_no_runtime_files(self):
        bindir = self.root / "bin"
        bindir.mkdir()
        fake = bindir / "fzf"
        fake.write_text(f"#!{sys.executable}\n" + '''import os, subprocess, sys
from pathlib import Path
rows = sys.stdin.read().splitlines()
assert "AGENT_LOG_PICKER_SOCKET" not in os.environ
assert not list(Path(os.environ["XDG_RUNTIME_DIR"]).iterdir())
path = os.environ["TEST_TRANSCRIPT"]
binary = os.environ["TEST_BINARY"]
def run(*args):
    return subprocess.check_output([binary, *args], text=True)
assert "FinalAnswer" in run("_show", "5", path)
assert "ToolOnly" in run("_full", path)
assert "ToolOnly" not in run("_full", path, "--no-tools")
source = Path(path)
before = source.stat()
source.write_text(source.read_text().replace("FinalAnswer", "FreshAnswer"))
os.utime(source, ns=(before.st_atime_ns, before.st_mtime_ns))
assert "FreshAnswer" in run("_show", "5", path)
assert "FinalAnswer" not in run("_full", path)
assert run("_sessions", "--all", "--query", "freshanswer")
assert not run("_sessions", "--all", "--query", "finalanswer")
assert not Path(os.environ["XDG_CACHE_HOME"]).exists()
assert not list(Path(os.environ["XDG_RUNTIME_DIR"]).iterdir())
print("alt-i\\n" + rows[0])
''')
        fake.chmod(0o700)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env["PATH"],
                   TEST_TRANSCRIPT=str(self.files[2]), TEST_BINARY=BINARY)
        env.pop("AGENT_LOG_PICKER_SOCKET", None)
        self.assertEqual(self.run_log("--all", env=env).strip(), "codex")
        self.assertFalse((self.root / "cache").exists())
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_metadata_is_complete_not_a_head_tail_sample(self):
        path = self.files[0]
        records = [json.loads(line) for line in path.read_text().splitlines()]
        records += [
            {"type": "ai-title", "aiTitle": "Superseded title"},
            {"type": "assistant", "timestamp": "2026-08-15T10:00:00Z",
             "message": {"model": "first-model", "content": "x" * 300000}},
            {"type": "ai-title", "aiTitle": "Middle title Café"},
            {"type": "assistant", "timestamp": "2026-08-12T10:00:00Z",
             "message": {"model": "later-model", "content": "y" * 300000}},
        ]
        path.write_text("\n".join(map(json.dumps, records)) + "\n{unfinished")
        rows = self.run_log("--all", "--list").splitlines()
        self.assertIn("Middle title Café", rows[0])
        self.assertIn("2026-08-15", rows[0])
        header = self.run_log("_show", "1", path)
        self.assertIn("first-model", header)
        self.assertNotIn("later-model", header)
        self.assertNotIn("Superseded title", header)

    def test_projection_falls_back_for_unusual_valid_json(self):
        path = self.files[0]
        # Duplicate fields and non-object records have the original reader's
        # semantics, even when they cannot use the borrowing projection.
        path.write_text('42\n{"type":"user","cwd":' + json.dumps(str(self.project))
                        + ',"timestamp":"2026-08-20T12:00:00Z",'
                        + '"message":null,"message":{"content":"FallbackTitle"}}\n')
        self.assertIn("FallbackTitle", self.run_log("--all", "--list"))
        self.assertIn("FallbackTitle", self.run_log("_show", "2", path))

    def test_search_prefilter_never_drops_decoded_matches(self):
        path = self.files[2]
        texts = ['MiXeDCase', 'AB\bCD', 'AB\fCD', 'AB\x1b[31mCD',
                 'KING', 'İSTANBUL', 'a "quoted" word', 'Café', 'Back\\Slash']
        with path.open("a") as out:
            for value in texts:
                out.write(json.dumps({"type": "response_item", "payload": {
                    "type": "message", "role": "assistant", "content": value}}) + "\n")
        for query in ['mixedcase', 'abcd', 'king', 'istanbul', 'i̇stanbul',
                      '"quoted"', 'CAFÉ', 'Back\\Slash']:
            # Unicode lowercase of İ is i + combining dot, not plain i.
            expected = [] if query == 'istanbul' else ['codex']
            self.assertEqual(self.ids("--query", query), expected, query)
        # Raw JSON keys are not conversation text.
        self.assertEqual(self.ids("--query", "response_item"), [])

    def test_offsets_ignore_invalid_lines_and_paths_stay_valid(self):
        path = self.files[2]
        path.write_text("\nnot json\n" + path.read_text() + "{unfinished")
        self.run_log("--list", path)
        self.assertIn("FinalAnswer", self.run_log("_show", "5", path))
        self.assertIn("DeepThought Café", self.run_log("_show", "3", path))
        # Relative transcript paths must not leak into subsequent session listings.
        self.run_log("--turn", "1", self.files[0].name, cwd=self.files[0].parent)
        listed = self.run_log("--list")
        self.assertIn(str(self.files[0]), listed)
        self.assertEqual(self.run_log("--list", "."), listed)

    def capture_picker(self, args, mode="session"):
        bindir = self.root / "bin"
        bindir.mkdir(exist_ok=True)
        fake = bindir / "fzf"
        fake.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
rows = sys.stdin.read().splitlines()
Path(os.environ["CAPTURE"]).write_text(json.dumps([sys.argv[1:], rows]))
if os.environ["PICKER_MODE"] == "session":
    print("alt-i\\n" + rows[0])
else:
    print("\\n".join(reversed(rows[:2])))
''')
        fake.chmod(0o700)
        capture = self.root / "capture.json"
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env["PATH"],
                   CAPTURE=str(capture), PICKER_MODE=mode)
        output = self.run_log(*args, env=env)
        return output, *json.loads(capture.read_text())

    def test_picker_reload_retains_scope_agent_and_literal_query(self):
        output, args, rows = self.capture_picker(["--agent", "codex", self.project])
        self.assertEqual(output.strip(), "codex")
        self.assertIn("--no-sort", args)
        self.assertIn("--disabled", args)
        self.assertIn("--with-nth=1", args)
        self.assertNotIn("ToolOnly", rows[0])
        binding = next(a for a in args if a.startswith("--bind=change:reload("))
        command = binding[len("--bind=change:reload("):-1]
        for query in ["toolonly", "$(touch pwned)", "it's absent", "no-match"]:
            result = subprocess.run(["sh", "-c", command.replace("{q}", shlex.quote(query))],
                                    env=dict(self.env, FZF_PROMPT="conversation> "), cwd=self.root,
                                    capture_output=True, text=True, check=True)
            self.assertEqual(bool(result.stdout.strip()), query == "toolonly")
        self.assertFalse((self.root / "pwned").exists())
        # Widening the scope must persist over subsequent query changes.
        self.assertEqual(len(self.run_log("_sessions", "--query", "first", self.root,
                                         env=dict(self.env, FZF_PROMPT="all> ")).splitlines()), 3)

    def test_turn_picker_search_and_selection_stay_newest_first(self):
        output, args, rows = self.capture_picker([self.files[2]], mode="turn")
        self.assertIn("--no-sort", args)
        self.assertIn("--bind=start:first", args)
        self.assertFalse(any("ctrl-o" in a for a in args))
        self.assertLess(output.index("FinalAnswer"), output.index("ToolOnly"))
        # Real fzf, without a terminal: matching must retain input order even
        # when a shorter older match would normally score higher.
        fzf = shutil.which("fzf")
        query_args = [a for a in args if a in ("--no-sort", "--exact", "-i", "--ansi")]
        result = subprocess.run([fzf, *query_args, "--filter=needle"],
                                input="newest long needle text\nolder needle\n", text=True,
                                capture_output=True, env=self.env, check=True)
        self.assertEqual(result.stdout.splitlines()[0], "newest long needle text")


if __name__ == "__main__":
    unittest.main()
