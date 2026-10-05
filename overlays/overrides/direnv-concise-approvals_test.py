"""Exercise approval output and enforcement with the actual patched binary."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


direnv = str(Path(sys.argv[1]).resolve())


def check(paths):
    with tempfile.TemporaryDirectory(prefix="direnv-approval-") as temporary:
        root = Path(temporary)
        project = root / "project"
        project.mkdir()
        config = root / "config"
        config.mkdir()
        (config / "direnv.toml").write_text(
            '[global]\nlog_format = "[approval] %s"\nlog_filter = ""\n'
        )
        env = {k: v for k, v in os.environ.items() if not k.startswith("DIRENV_")}
        env.update(HOME=str(root), DIRENV_CONFIG=str(config), XDG_DATA_HOME=str(root / "data"))
        # Isolate from any system/user direnvrc and declare the fixture inputs.
        (config / "direnvrc").write_text("")
        (project / ".envrc").write_text(
            "require_allowed " + " ".join("'" + p.replace("'", "'\\''") + "'" for p in paths)
            + "\nprintf activated >> activation-log\nexport APPROVAL_FIXTURE=loaded\n"
        )
        for index, name in enumerate(paths):
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"input {index}\n")

        def run(*args, success=True):
            result = subprocess.run(
                [direnv, *args], cwd=project, env=env, capture_output=True, text=True, timeout=20
            )
            if success:
                assert result.returncode == 0, result.stdout + result.stderr
            return result

        def load():
            result = run("export", "json")
            for key, value in json.loads(result.stdout or "{}").items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
            return result

        run("allow")
        result = load()
        assert "APPROVAL_FIXTURE" not in env
        assert not (project / "activation-log").exists()
        assert env["DIRENV_REQUIRED"].split(":") == paths
        message = next(line for line in result.stderr.splitlines() if "approval. Run" in line)
        assert message.startswith("[approval] "), message
        assert len(message) < 350, message
        assert "direnv status --required" in message and "direnv allow" in message
        if len(paths) > 3:
            assert f"{len(paths)} files" in message
            assert f"and {len(paths) - 3} more" in message
            assert paths[3] not in message
        elif len(paths) == 1:
            assert "requires approval" in message

        status = run("status", "--required")
        assert not status.stderr
        assert len(status.stdout.splitlines()) == len(paths)
        assert "\x1b" not in status.stdout
        # The detail command must not execute .envrc.
        assert not (project / "activation-log").exists()
        if len(paths) > 3:
            assert json.dumps(paths[-1]) in status.stdout
        json.loads(run("status", "--json").stdout)
        assert "Found RC path" in run("status").stdout

        allowed = run("allow")
        assert not allowed.stdout
        assert len(allowed.stderr.splitlines()) == 1, allowed.stderr
        assert allowed.stderr.startswith("[approval] allowed ")
        assert len(allowed.stderr) < 250
        load()
        assert env["APPROVAL_FIXTURE"] == "loaded"
        assert not env.get("DIRENV_REQUIRED")
        assert not run("status", "--required").stdout
        assert (project / "activation-log").read_text() == "activated"

        # A file hidden by the preview must still invalidate approval.
        changed = project / paths[-1]
        changed.write_text("changed\n")
        os.utime(changed, (time.time() + 5,) * 2)
        load()
        assert "APPROVAL_FIXTURE" not in env
        assert env["DIRENV_REQUIRED"] == paths[-1]
        assert (project / "activation-log").read_text() == "activated"

        # Failed approvals must not print a success summary.
        changed.unlink()
        failed = run("allow", success=False)
        assert failed.returncode != 0
        assert "required file does not exist" in failed.stderr
        assert "[approval] allowed " not in failed.stderr
        changed.write_text("restored\n")
        run("allow")
        load()
        assert env["APPROVAL_FIXTURE"] == "loaded"


for count in (1, 3, 4, 250):
    check([f"inputs/file-{index:03}.nix" for index in range(count)])
check(["/".join(["long" * 15] * 4) + "/input.nix"])
check(["with space.nix", "with'quote.nix", "with\nnewline\x1b.nix"])
print("passed: bounded approval output, complete details, and approval enforcement")
