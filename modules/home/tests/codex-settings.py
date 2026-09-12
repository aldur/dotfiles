"""Run actual Home Manager activation fragments against disposable homes."""

import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import tomllib
import unittest


CROSTINI_ACTIVATION, GENERIC_ACTIVATION = sys.argv[1:]
del sys.argv[1:]

EXISTING = '''# Keep my configuration comments.
model = "gpt-6-astra"
model_reasoning_effort = "high"

[projects."/home/aldur/dotfiles"]
trust_level = "trusted"

[tui]
theme = "custom"
notifications = false
animations = true
status_line = ["model-name"]

[tui.model_availability_nux]
gpt-6-astra = 4

[mcp_servers.example]
command = "example-mcp"
args = ["--local"]
'''


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "home"
        self.home.mkdir()
        self.target = self.home / ".codex/config.toml"

    def seed(self, text):
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.target.write_text(text)

    def activate(self, script=CROSTINI_ACTIVATION, *, dry_run=False, success=True):
        env = dict(os.environ, HOME=str(self.home))
        env.pop("DRY_RUN", None)
        if dry_run:
            env["DRY_RUN"] = "1"
        result = subprocess.run([script], env=env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def read(self):
        return tomllib.loads(self.target.read_text())

    def assert_preserved(self):
        result = self.read()
        original = tomllib.loads(EXISTING)
        for key in ("model", "model_reasoning_effort", "projects", "mcp_servers"):
            self.assertEqual(result[key], original[key])
        for key in ("theme", "notifications", "animations", "model_availability_nux"):
            self.assertEqual(result["tui"][key], original["tui"][key])
        self.assertIn("# Keep my configuration comments.", self.target.read_text())
        self.assertFalse(result["tui"]["whimsy"])
        self.assertFalse(result["analytics"]["enabled"])
        self.assertIn("current-dir", result["tui"]["status_line"])
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)
        self.assertFalse(self.target.is_symlink())

    def test_fresh_install(self):
        self.activate()
        self.assertFalse(self.read()["tui"]["whimsy"])
        self.assertNotIn("animations", self.read()["tui"])
        self.assertEqual(stat.S_IMODE(self.target.stat().st_mode), 0o600)

    def test_migrate_existing_config_without_whimsy(self):
        self.seed(EXISTING)
        self.activate()
        self.assert_preserved()

    def test_migrate_explicit_whimsy_true(self):
        self.seed(EXISTING.replace("[tui]\n", "[tui]\nwhimsy = true\n"))
        self.activate()
        self.assert_preserved()

    def test_migrate_previous_managed_settings(self):
        self.seed(EXISTING)
        self.activate(GENERIC_ACTIVATION)
        expected = self.read()
        expected["tui"]["whimsy"] = False
        self.activate()
        self.assertEqual(self.read(), expected)
        self.assert_preserved()

    def test_repeated_activation_preserves_runtime_changes(self):
        self.seed(EXISTING)
        self.activate()
        self.assert_preserved()
        with self.target.open("a") as config:
            config.write('\n[projects."/new/project"]\ntrust_level = "trusted"\n')
        before = self.target.read_bytes()
        self.activate()
        self.assertEqual(self.target.read_bytes(), before)

    def test_generic_host_does_not_introduce_whimsy(self):
        self.seed(EXISTING)
        self.activate(GENERIC_ACTIVATION)
        self.assertNotIn("whimsy", self.read()["tui"])

    def test_generic_host_preserves_user_whimsy_choice(self):
        for value in ("true", "false"):
            with self.subTest(whimsy=value):
                self.seed(EXISTING.replace("[tui]\n", f"[tui]\nwhimsy = {value}\n"))
                self.activate(GENERIC_ACTIVATION)
                self.assertEqual(self.read()["tui"]["whimsy"], value == "true")

    def test_dry_run_does_not_create_configuration(self):
        self.activate(dry_run=True)
        self.assertFalse(self.target.parent.exists())

    def test_dry_run_does_not_modify_existing_configuration(self):
        self.seed(EXISTING)
        before = self.target.read_bytes()
        before_stat = self.target.stat()
        self.activate(dry_run=True)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.target.stat().st_mtime_ns, before_stat.st_mtime_ns)
        self.assertEqual(self.target.stat().st_mode, before_stat.st_mode)

    def test_migrate_legacy_readonly_symlink(self):
        legacy = self.home / "legacy-managed.toml"
        legacy.write_text(EXISTING)
        legacy.chmod(0o444)
        self.target.parent.mkdir()
        self.target.symlink_to(legacy)
        self.activate()
        self.assert_preserved()
        self.assertEqual(legacy.read_text(), EXISTING)
        self.assertEqual(stat.S_IMODE(legacy.stat().st_mode), 0o444)

    def test_malformed_existing_configuration_fails_without_data_loss(self):
        self.seed("[tui\nwhimsy = true\n")
        before = self.target.read_bytes()
        self.activate(success=False)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])


if __name__ == "__main__":
    unittest.main(verbosity=2)
