"""Fast preflight tests; real boot/provision/reboot coverage lives in e2e.py."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory(prefix="macos-vm-test.") as work:
    state = Path(work) / "state with spaces"
    log = Path(work) / "calls.jsonl"

    def run(*args, ok=False, fail=""):
        log.write_text("")
        result = subprocess.run(
            [sys.argv[1], "--dir", str(state), *args],
            env=dict(os.environ, VM_TEST_LOG=str(log), VM_TEST_FAIL=fail),
            text=True, capture_output=True,
        )
        assert (result.returncode == 0) == ok, result.stderr
        return result, [json.loads(line) for line in log.read_text().splitlines()]

    for args in (
        ("--name", "../escape"), ("--name", "-bad"),
        ("--memory", "0"), ("--cores", "oops"),
        ("--gui", "--headless"), ("--ip", "--stop"),
        ("--ssh", "--check"), ("--unknown",),
    ):
        _, calls = run(*args)
        assert not calls, calls
    assert not (state / "vms").exists()

    # Network/image failure propagates and permits retry without a stale lock.
    for _ in range(2):
        result, calls = run(fail="clone")
        assert result.returncode == 42
        assert calls[0][0] == "clone" and len(calls) == 1
        assert not (state / ".macos-vm-macos" / "lock").exists()

    # Management never creates a missing VM or requires a launcher lock.
    _, calls = run("--ip")
    assert calls == [["ip", "macos"]]
    assert not (state / "vms").exists()
    (state / "vms" / "macos").mkdir(parents=True)
    lock = state / ".macos-vm-macos" / "lock"
    lock.mkdir()
    _, calls = run()
    assert not calls
    result, calls = run("--ip", ok=True)
    assert result.stdout.strip() == "192.0.2.10"
    _, calls = run("--stop", ok=True)
    assert calls == [["stop", "macos"]]
    lock.rmdir()

print("macos-vm preflight checks passed")
