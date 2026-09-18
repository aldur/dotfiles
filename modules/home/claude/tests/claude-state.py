"""Defensive state-I/O checks, entirely within a disposable fixture."""

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


source, jq = sys.argv[1:]
spec = importlib.util.spec_from_file_location("claude_state", source)
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class StateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.parent = self.home / ".claude"
        self.parent.mkdir(mode=0o700)
        self.target = self.parent / "settings.json"
        self.target.write_text('{"user":true}')

    def invoke(self, *args, content=None, success=True):
        result = subprocess.run([sys.executable, "-I", source, "--home", str(self.home), *args],
                                input=content, capture_output=True, timeout=5)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def test_permission_error_identifies_path_without_mutating_it(self):
        for path in (self.home, self.parent, self.target):
            with self.subTest(path=path):
                original_mode = stat.S_IMODE(path.stat().st_mode)
                shared_mode = original_mode | 0o020
                path.chmod(shared_mode)
                result = self.invoke("update", ".claude/settings.json", jq, '.', success=False)
                self.assertIn(str(path), result.stderr.decode())
                self.assertIn(f"{shared_mode:04o}", result.stderr.decode())
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), shared_mode)
                path.chmod(original_mode)

    def test_update_preserves_inode_and_sets_permissions(self):
        inode = self.target.stat().st_ino
        managed = self.root / "managed.json"
        managed.write_text('{"managed":true}')
        self.invoke("update", ".claude/settings.json", jq, '-s', '.[0] * .[1]', '-', str(managed))
        self.assertEqual(json.loads(self.target.read_text()), {"user": True, "managed": True})
        self.assertEqual(self.target.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)

    def test_missing_empty_and_shorter_writes(self):
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture 12345\n")
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture 1\n")
        result = self.invoke("read", ".claude/yolo-refresh")
        self.assertEqual(result.stdout, b"fixture 1\n")
        self.invoke("--skip-empty", "update", ".claude.json", jq, '.projects = {}')
        self.assertFalse((self.home / ".claude.json").exists())
        (self.home / ".claude.json").touch()
        self.invoke("--skip-empty", "update", ".claude.json", jq, '.projects = {}')
        self.assertEqual((self.home / ".claude.json").read_bytes(), b"")
        self.invoke("update", ".claude.json", jq, '.projects = {}')
        self.assertEqual(json.loads((self.home / ".claude.json").read_text()), {"projects": {}})

    def test_old_temporary_names_are_unused(self):
        for name in ("settings.json.tmp", "yolo-refresh.next"):
            (self.parent / name).write_text("untouched")
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture 1\n")
        self.invoke("update", ".claude/settings.json", jq, '.')
        for name in ("settings.json.tmp", "yolo-refresh.next"):
            self.assertEqual((self.parent / name).read_text(), "untouched")

    def test_create_directory_and_missing_read(self):
        self.target.unlink()
        self.parent.rmdir()
        self.assertEqual(self.invoke("read", ".claude/yolo-refresh").stdout, b"")
        self.assertFalse(self.parent.exists())
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture 1\n")
        self.assertEqual(stat.S_IMODE(self.parent.stat().st_mode), 0o700)

    def test_failed_transform_leaves_contents_and_mode(self):
        before = self.target.read_bytes(), self.target.stat().st_mode
        self.invoke("update", ".claude/settings.json", jq, 'error("fixture failure")', success=False)
        self.assertEqual((self.target.read_bytes(), self.target.stat().st_mode), before)
        self.invoke("--skip-empty", "update", ".claude/settings.json", "/missing-fixture-command",
                    success=False)

    def test_rejects_file_symlink_hardlink_fifo_directory(self):
        fixture = self.root / "unrelated"
        fixture.write_text("untouched")
        before = fixture.read_bytes(), fixture.stat().st_mode
        for kind in ("symlink", "hardlink", "fifo", "directory"):
            with self.subTest(kind=kind):
                self.target.unlink()
                if kind == "symlink":
                    self.target.symlink_to(fixture)
                elif kind == "hardlink":
                    os.link(fixture, self.target)
                elif kind == "fifo":
                    os.mkfifo(self.target)
                else:
                    self.target.mkdir()
                self.invoke("update", ".claude/settings.json", jq, '.', success=False)
                self.assertEqual((fixture.read_bytes(), fixture.stat().st_mode), before)
                if kind == "directory":
                    self.target.rmdir()
                    self.target.touch()

    def test_stamp_read_and_write_reject_symlinks(self):
        (self.parent / "yolo-refresh").symlink_to(self.target)
        before = self.target.read_bytes(), self.target.stat().st_mode
        self.invoke("read", ".claude/yolo-refresh", success=False)
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture 1\n", success=False)
        self.assertEqual((self.target.read_bytes(), self.target.stat().st_mode), before)

    def test_rejects_parent_symlink_and_shared_permissions(self):
        self.target.unlink()
        self.parent.rmdir()
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.parent.symlink_to(elsewhere, target_is_directory=True)
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture\n", success=False)
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.parent.unlink()
        self.parent.mkdir(mode=0o700)
        self.parent.chmod(0o777)
        self.invoke("write", ".claude/yolo-refresh", content=b"fixture\n", success=False)

    def test_rejects_wrong_owner_and_shared_file(self):
        with state.state_file(self.home, ".claude/settings.json", write=True) as fd:
            with patch.object(state.os, "getuid", return_value=os.getuid() + 1):
                with self.assertRaises(ValueError):
                    state.validate(fd)
        self.target.chmod(0o666)
        self.invoke("update", ".claude/settings.json", jq, '.', success=False)

    def test_descriptor_stays_pinned_and_links_are_rechecked(self):
        other = self.root / "unrelated"
        other.write_text("untouched")
        with state.state_file(self.home, ".claude/settings.json", write=True) as fd:
            saved = self.parent / "saved.json"
            self.target.rename(saved)
            self.target.symlink_to(other)
            state.write(fd, b"updated")
            self.assertEqual(saved.read_bytes(), b"updated")
            self.assertEqual(other.read_text(), "untouched")
            os.link(saved, self.parent / "alias.json")
            with self.assertRaises(ValueError):
                state.write(fd, b"rejected")
            self.assertEqual(saved.read_bytes(), b"updated")


unittest.main(argv=[sys.argv[0]])
