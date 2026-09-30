"""Regression tests for discovery, search, uncached reads and fzf."""

import json
import os
from pathlib import Path
import contextlib
import errno
import fcntl
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
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
        self.env.pop("FZF_PREVIEW_LABEL", None)
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

    def test_codex_rendering_has_no_stale_warning(self):
        warning = ("The Codex reader is built from the published rollout format and has "
                   "not been checked against a real session.")
        env = dict(self.env)
        env.pop("NO_COLOR", None)
        for command in ["--full", "_preview"]:
            for color in ["always", "never"]:
                with self.subTest(command=command, color=color):
                    output = self.run_log(command, self.files[2], f"--color={color}", env=env)
                    self.assertNotIn(warning, output)
                    self.assertIn("FinalAnswer", output)
        # Remove the generated warning, not matching text in real messages.
        with self.files[2].open("a") as out:
            out.write(json.dumps({"type": "response_item", "payload": {
                "type": "message", "role": "assistant", "content": warning}}) + "\n")
        self.assertEqual(self.run_log("--full", self.files[2]).count(warning), 1)

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

    def test_codex_titles_use_requests_not_injected_setup(self):
        path = self.files[2]
        meta = json.loads(path.read_text().splitlines()[0])
        agents = "# AGENTS.md instructions for /tmp/project\n\n<INSTRUCTIONS>\nSetupOnlyNeedle\n</INSTRUCTIONS>"
        context = "<environment_context>\n<cwd>/tmp/project</cwd>\n</environment_context>"
        instructions = "<user_instructions>\nMoreSetupOnly\n</user_instructions>"

        def message(content):
            return {"type": "response_item", "payload": {
                "type": "message", "role": "user", "content": content}}

        def blocks(*texts):
            return [{"type": "input_text", "text": text} for text in texts]

        cases = [
            ([agents, context, instructions, "Fix preview scrolling", "A later request"],
             "Fix preview scrolling"),
            ([blocks(agents, context), blocks("Search", "Café bodies")], "Search Café bodies"),
            ([blocks(agents, context, "Make scrolling work")], "Make scrolling work"),
            ([agents + "\n" + context + "\nActual request in the same block"],
             "Actual request in the same block"),
            (["<environment_context>\nIncomplete setup", "Keep this request"], "Keep this request"),
            ([blocks("<environment_context>\nIncomplete", "Real request")], "Real request"),
            ([agents, context], "(no user request yet)"),
            (["Explain <environment_context> and AGENTS.md instructions"],
             "Explain <environment_context> and AGENTS.md instructions"),
            (["# AGENTS.md instructions for a new project\nPlease help write them"],
             "# AGENTS.md instructions for a new project Please help write them"),
            (["```xml\n<environment_context>\n```\nExplain this"],
             "```xml <environment_context> ``` Explain this"),
            (["# Context from my IDE setup:\n## Open tabs:\n- file.rs\n\n## My request for Codex:\nFix the parser"],
             "Fix the parser"),
            ([[{"type": "input_image", "image_url": "data:example"}], "Describe this image"],
             "Describe this image"),
        ]
        for contents, expected in cases:
            # Valid unusual JSON exercises the full-parser fallback as well as
            # the fast metadata projection; they must choose the same title.
            for fallback in [False, True]:
                with self.subTest(expected=expected, fallback=fallback):
                    records = ([42] if fallback else []) + [meta, *map(message, contents)]
                    path.write_text("\n".join(map(json.dumps, records)) + "\n")
                    rows = self.run_log("--all", "--agent", "codex", "--list").splitlines()
                    self.assertEqual(len(rows), 1)
                    self.assertTrue(rows[0].split("\t")[0].endswith(expected), rows[0])
                    self.assertIn(f"# {expected}\n", self.run_log("--full", path))

        # Filtering title candidates must not remove setup from search, turns
        # or exported text, nor skip a setup-only conversation altogether.
        path.write_text("\n".join(map(json.dumps, [meta, message(agents), message(context)])) + "\n")
        self.assertEqual(self.ids("--query", "SetupOnlyNeedle"), ["codex"])
        self.assertIn("SetupOnlyNeedle", self.run_log("--full", path))
        self.assertIn("SetupOnlyNeedle", self.run_log("--turn", "1", path))
        self.assertIn("(no user request yet)", self.run_log("--all", "--list"))
        with path.open("a") as out:
            out.write(json.dumps(message("A newly arrived request")) + "\n")
        self.assertIn("A newly arrived request", self.run_log("--all", "--list"))
        self.assertEqual(self.ids("--query", "SetupOnlyNeedle"), ["codex"])
        self.assertFalse((self.root / "cache").exists())

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
assert not list(Path(os.environ["XDG_RUNTIME_DIR"]).iterdir())
path = os.environ["TEST_TRANSCRIPT"]
binary = os.environ["TEST_BINARY"]
def run(*args):
    return subprocess.check_output([binary, *args], text=True)
assert "FinalAnswer" in run("_show", "5", path)
assert "ToolOnly" in run("--full", path)
assert "ToolOnly" not in run("--full", path, "--no-tools")
source = Path(path)
before = source.stat()
source.write_text(source.read_text().replace("FinalAnswer", "FreshAnswer"))
os.utime(source, ns=(before.st_atime_ns, before.st_mtime_ns))
assert "FreshAnswer" in run("_show", "5", path)
assert "FinalAnswer" not in run("_preview", path)
assert run("_sessions", "--all", "--query", "freshanswer")
assert not run("_sessions", "--all", "--query", "finalanswer")
assert not Path(os.environ["XDG_CACHE_HOME"]).exists()
assert not list(Path(os.environ["XDG_RUNTIME_DIR"]).iterdir())
print("alt-i\\n" + rows[0])
''')
        fake.chmod(0o700)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env["PATH"],
                   TEST_TRANSCRIPT=str(self.files[2]), TEST_BINARY=BINARY)
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
        self.assertIn("--bind=start:hide-header+first", args)
        self.assertIn("--no-wrap", args)
        self.assertIn("--no-hscroll", args)
        self.assertIn("--with-nth=2,3,4,5", args)
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

    def test_picker_chrome_and_preview_bindings(self):
        for mode, command in [("session", ["--all"]), ("turn", [self.files[2]])]:
            with self.subTest(mode=mode):
                _, args, _ = self.capture_picker(command, mode=mode)
                self.assertIn("--gap=0", args)
                self.assertIn("--bind=f1:toggle-header", args)
                self.assertIn("--bind=alt-p:toggle-preview", args)
                self.assertIn("--bind=pgup:preview-page-up,pgdn:preview-page-down", args)
                self.assertIn("--bind=preview-scroll-up:preview-up,preview-scroll-down:preview-down", args)
                footer = next(a for a in args if a.startswith("--footer="))
                self.assertLess(len(footer), 60)
                preview = next(a for a in args if a.startswith("--preview-window="))
                self.assertIn("<60(down,50%,border-top", preview)
                self.assertEqual("hidden" in preview, mode == "session")
                header = next(a for a in args if a.startswith("--header="))[len("--header="):]
                help_text = self.run_log("--help")
                for line in header.splitlines():
                    self.assertIn(line, help_text)
                self.assertTrue(any(a.startswith("--bind=alt-e:transform(") for a in args))
                self.assertFalse(any(a.startswith("--bind=alt-c:") for a in args))
        # Hide repeated metadata only in previews, not copied/exported text.
        body = self.run_log("_preview", self.files[2], "--turn", "5")
        self.assertIn("FinalAnswer", body)
        self.assertNotIn("session:", body)
        self.assertIn("session:", self.run_log("_show", "5", self.files[2]))

    def test_rich_rendering_and_folding_for_all_agents(self):
        for name, path in zip(["claude", "pi", "codex"], self.files):
            with self.subTest(agent=name):
                records = [json.loads(line) for line in path.read_text().splitlines()]
                stamp = "2026-08-10T13:00:00Z"
                if name == "codex":
                    records += [
                        {"type": "turn_context", "payload": {"model": "TESTMODEL"}},
                        {"type": "response_item", "payload": {"type": "function_call",
                         "name": "TESTTOOL", "arguments": json.dumps({"command": "ls"})}},
                    ]
                    expected = ["DeepThought", "ToolOnly", "FinalAnswer", "TESTTOOL"]
                    hidden = ["DeepThought", "ToolOnly", '"command"']
                else:
                    call, result, argument = (("tool_use", "tool_result", "input") if name == "claude"
                                               else ("toolCall", "toolResult", "arguments"))
                    blocks = [{"type": "thinking", "thinking": "THINKMARK"},
                              {"type": call, "name": "TESTTOOL", argument: {"command": "ls"}},
                              {"type": "text", "text": "ANSWERMARK"}]
                    assistant = {"role": "assistant", "model": "TESTMODEL", "content": blocks}
                    tool_result = {"role": "user", "content": [{"type": result, "content": "RESULTMARK"}]}
                    empty_thinking = {"role": "assistant", "content": [
                        {"type": "thinking", "thinking": "", "signature": "HIDDENSIGNATURE"},
                        {"type": "text", "text": "TEXTONLYMARK"}]}
                    if name == "pi":
                        records.append({"type": "model_change", "provider": "test", "modelId": "TESTMODEL"})
                    records += [{"type": message["role"] if name == "claude" else "message",
                                 "timestamp": stamp, "message": message}
                                for message in [assistant, tool_result, empty_thinking]]
                    expected = ["THINKMARK", "ANSWERMARK", "RESULTMARK", "TESTTOOL", "TEXTONLYMARK"]
                    hidden = ["THINKMARK", "RESULTMARK", '"command"']
                path.write_text("\n".join(map(json.dumps, records)) + "\n")
                full = self.run_log("--full", path)
                folded = self.run_log("_preview", path)
                expanded = self.run_log("_preview", path, "--expanded")
                self.assertEqual(expanded, self.run_log("_page", path, env=dict(self.env, PAGER="cat")))
                for marker in expected:
                    self.assertIn(marker, full)
                    self.assertIn(marker, expanded)
                for marker in hidden:
                    self.assertNotIn(marker, folded)
                self.assertIn("▸", folded)
                self.assertIn("▾", expanded)
                self.assertIn('"command": "ls"', expanded)
                self.assertNotIn("HIDDENSIGNATURE", full)
                self.assertNotIn("A pi session records", full)
                dialogue = self.run_log("--full", path, "--no-tools")
                self.assertNotIn("TESTTOOL", dialogue)
                self.assertNotIn("RESULTMARK", dialogue)
                self.assertNotIn("ToolOnly", dialogue)
                header = self.run_log("--turn", "1", path)
                self.assertIn(f"session: {name}", header)
                self.assertIn("TESTMODEL", header)
                self.assertIn("title:", header)
                self.assertIn("when:", header)
                self.assertEqual(full, self.run_log("--full", path, "--pretty"))

    def test_context_folding_preserves_search_and_export(self):
        path = self.files[2]
        source = ("Visible before\n<skills_instructions>\nSkillSecret\n</skills_instructions>\n"
                  "<environment_context>\n<cwd>/tmp/example</cwd>\n</environment_context>\n"
                  "<permissions instructions>\nPermissionSecret\n</permissions>\nVisible after")
        with path.open("a") as out:
            out.write(json.dumps({"type": "response_item", "payload": {
                "type": "message", "role": "user", "content": source}}) + "\n")
        folded = self.run_log("_preview", path, "--turn", "6")
        expanded = self.run_log("_preview", path, "--turn", "6", "--expanded")
        for label in ["Skills", "Environment", "Permissions"]:
            self.assertIn(f"▸ {label}", folded)
            self.assertIn(f"▾ {label}", expanded)
        for marker in ["SkillSecret", "PermissionSecret"]:
            self.assertNotIn(marker, folded)
            self.assertIn(marker, expanded)
            self.assertEqual(self.ids("--query", marker), ["codex"])
        self.assertIn("Cwd: /tmp/example", expanded)
        self.assertNotIn("<skills_instructions>", expanded)
        self.assertIn("Visible before", folded)
        self.assertIn("Visible after", folded)
        self.assertIn(source, self.run_log("--full", path))
        self.assertEqual(self.run_log("_preview", path, "--expanded"),
                         self.run_log("_page", path, env=dict(self.env, PAGER="cat")))
        self.assertFalse((self.root / "cache").exists())
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_tools_toggle_pager_and_jump_actions(self):
        path = self.project / "literal$(touch pwned) ' transcript.jsonl"
        path.write_text(self.files[2].read_text())
        for current, following, tools in [("turns> ", "dialogue> ", False), ("dialogue> ", "turns> ", True)]:
            action = self.run_log("_tools", path, env=dict(self.env, FZF_PROMPT=current))
            self.assertIn(f"change-prompt({following})", action)
            command = action[len("reload("):action.index(")+change-prompt")]
            rows = subprocess.check_output(["sh", "-c", command], env=self.env, cwd=self.project, text=True)
            self.assertEqual("ToolOnly" in rows, tools)
            self.assertEqual(rows.splitlines()[0].split("\t")[0], "5")
            paged = self.run_log("_page", path, env=dict(self.env, PAGER="cat", FZF_PROMPT=following))
            self.assertEqual("ToolOnly" in paged, tools)
        self.assertFalse((self.project / "pwned").exists())
        _, args, _ = self.capture_picker([path], mode="turn")
        self.assertIn("--bind=alt-g:last,alt-G:first", args)

    def test_pager_preserves_preview_rendering_without_a_second_renderer(self):
        bindir = self.root / "pager-bin"
        bindir.mkdir()
        # A fake less checks the default pager arguments and echoes the rendered
        # bytes. A fake bat fails if it is used to re-render that text.
        for name, code in [
            ("less", "assert sys.argv[1:] == ['-R']; sys.stdout.write(sys.stdin.read())"),
            ("bat", "sys.stdout.write('UNEXPECTED_SECOND_RENDERER')"),
        ]:
            program = bindir / name
            program.write_text(f"#!{sys.executable}\nimport sys\n{code}\n")
            program.chmod(0o700)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env["PATH"])
        env.pop("PAGER", None)
        env.pop("NO_COLOR", None)
        for path in self.files:
            for colour in ["always", "never"]:
                for no_tools in [False, True]:
                    with self.subTest(path=path.name, colour=colour, no_tools=no_tools):
                        flags = [f"--color={colour}", *(["--no-tools"] if no_tools else [])]
                        expected = self.run_log("_preview", path, "--expanded", *flags, env=env)
                        self.assertEqual(self.run_log("_page", path, *flags, env=env), expected)

    def test_colour_sanitization_errors_and_broken_pipes(self):
        path = self.files[0]
        records = [json.loads(line) for line in path.read_text().splitlines()]
        records[0]["message"]["content"] = "before \x1b[1mBOLD\x1b[0m after"
        records.append({"type": "ai-title", "aiTitle": "t \x1b[36mCOLOUR\x1b[0m x"})
        path.write_text("\n".join(map(json.dumps, records)) + "\n")
        env = dict(self.env)
        env.pop("NO_COLOR", None)
        for flags in [["--list"], ["--full"], ["--turn", "1"], ["_show", "1"]]:
            output = self.run_log(*flags, path)
            self.assertNotIn("\x1b", output)
            self.assertIn("before BOLD after", output)
        self.assertIn("t COLOUR x", self.run_log("--full", path))
        self.assertIn("\x1b", self.run_log("--turn", "1", path, "--color=always", env=env))
        self.assertNotIn("\x1b", self.run_log("--turn", "1", path, "--color=always"))
        result = subprocess.run([BINARY, "--turn", "99", str(path)], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        with subprocess.Popen([BINARY, "--list", str(path)], env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
            proc.stdout.close()
            self.assertEqual(proc.wait(), 0)
            self.assertEqual(proc.stderr.read(), b"")
        path.write_text('{"type":"started","key":"not-a-session"}\n')
        self.assertIn("unrecognised format", self.run_log("--full", path))

    def test_scope_matches_recorded_cwd_not_directory_name(self):
        other = self.root / "other-project"
        other.mkdir()
        path = self.files[0].with_name("elsewhere.jsonl")
        path.write_text(self.files[0].read_text().replace(str(self.project), str(other)))
        self.assertEqual(len(self.run_log("--list").splitlines()), 3)
        self.assertEqual(len(self.run_log("--all", "--list").splitlines()), 4)
        self.assertIn("elsewhere", self.run_log("--list", other))

    @contextlib.contextmanager
    def terminal_picker(self, *args, width=160, height=40):
        """A real fzf terminal, isolated from the user's transcripts/settings."""
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(self.project)
            env = dict(self.env, TERM="xterm-256color", SHELL=shutil.which("sh"))
            os.execve(BINARY, [BINARY, *map(str, args)], env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
        def read_until(pattern, timeout=8):
            output = b""
            plain = b""
            matched = False
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if not select.select([fd], [], [], 0.1)[0]:
                    if matched:
                        return plain
                    continue
                try:
                    chunk = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                output += chunk
                if b"\x1b[6n" in chunk:
                    os.write(fd, b"\x1b[1;1R")
                plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", output)
                matched = bool(re.search(pattern, plain))
            if matched:
                return plain
            self.fail(f"terminal did not show {pattern!r}: {output[-3000:]!r}")

        try:
            yield fd, read_until
        finally:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited != pid:
                os.kill(pid, signal.SIGTERM)
                os.waitpid(pid, 0)
            os.close(fd)

    def test_real_terminal_preview_scrolling_and_full_body_search(self):
        path = self.files[2]
        with path.open("a") as out:
            out.write(json.dumps({"type": "response_item", "payload": {
                "type": "message", "role": "assistant", "content":
                "\n".join(f"ScrollLine{i:03d}" for i in range(180))}}) + "\n")
        # Wide screens split side-by-side; narrow screens put preview below.
        for width in [160, 80]:
            with self.subTest(width=width), self.terminal_picker(path, width=width) as (fd, until):
                until(rb"ScrollLine000")
                os.write(fd, b"\x1b[6~")  # Page Down, not next result
                until(rb"ScrollLine0[2-6][0-9]")
                os.write(fd, b"\x1b[5~")  # Page Up
                until(rb"ScrollLine000")
                # Mouse wheel is routed by pane, not to a different turn.
                os.write(fd, f"\x1b[<65;{width - 10};30M".encode())
                until(rb"ScrollLine0[0-9][0-9]")
                os.write(fd, b"\x1b[1;2B")  # Shift-Down: another preview line
                until(rb"ScrollLine0[0-9][0-9]")
                # A match far beyond the clipped snippet must still be found.
                os.write(fd, b"ScrollLine179")
                until(rb"1/5")
                os.write(fd, b"\x1bOP")  # F1
                until(rb"toggle tools and dialogue")
                os.write(fd, b"\x1bOP")
                os.write(fd, b"\r")
                result = until(rb"ScrollLine179")
                self.assertIn(b"session: codex", result)

    def test_real_terminal_optional_session_preview(self):
        with self.terminal_picker("--all") as (fd, until):
            initial = until(rb"3/3")
            self.assertNotIn(b"DeepThought", initial)
            os.write(fd, b"\x1bp")  # Alt-P
            until(rb"thinking")
            os.write(fd, b"\x1be")  # Alt-E: reveal folded details
            until(rb"DeepThought")
            os.write(fd, b"\x1be")  # The same key collapses them again.
            collapsed = until("▸ thinking".encode())
            self.assertNotIn(b"DeepThought", collapsed)
            os.write(fd, b"\x1be")
            until(rb"DeepThought")
            os.write(fd, b"toolonly")
            until(rb"1/1")
            os.write(fd, b"\x1bi")  # Alt-I returns the same session
            until(rb"codex\r\n$")

    def test_real_terminal_expand_collapse_and_search(self):
        path = self.files[2]
        content = ("Main request stays visible. " * 5 +
                   "\n<skills_instructions>\nExpandableSecret\n</skills_instructions>\nLast visible line")
        with path.open("a") as out:
            out.write(json.dumps({"type": "response_item", "payload": {
                "type": "message", "role": "user", "content": content}}) + "\n")
        for width in [80, 160]:
            with self.subTest(width=width), self.terminal_picker(path, width=width) as (fd, until):
                collapsed = until("▸ Skills".encode())
                self.assertNotIn(b"ExpandableSecret", collapsed)
                for _ in range(3):
                    os.write(fd, b"\x1be")
                    until(rb"ExpandableSecret")
                    os.write(fd, b"\x1be")
                    collapsed = until("▸ Skills".encode())
                    self.assertNotIn(b"ExpandableSecret", collapsed)
                os.write(fd, b"ExpandableSecret")
                until(rb"1/5")
                os.write(fd, b"\r")
                exported = until(rb"</skills_instructions>")
                self.assertIn(b"ExpandableSecret", exported)

    def test_turn_search_has_no_artificial_snippet_boundary(self):
        path = self.files[0]
        record = json.loads(path.read_text().splitlines()[0])
        record["message"]["content"] = "x" * 197 + "BoundaryNeedle" + "y" * 300
        path.write_text(json.dumps(record) + "\n")
        _, args, rows = self.capture_picker([path], mode="turn")
        options = [a for a in args if a.startswith("--with-nth=") or a in ("--delimiter=\t", "--ansi", "--exact", "-i", "--no-sort")]
        result = subprocess.run(["fzf", *options, "--filter=BoundaryNeedle"], input="\n".join(rows),
                                text=True, capture_output=True, env=self.env, check=True)
        self.assertEqual(result.stdout.split("\t")[0], "1")


if __name__ == "__main__":
    unittest.main()
