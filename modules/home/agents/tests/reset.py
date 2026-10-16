import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


activation, source, entrypoint, command, closure = sys.argv[1:]
expected = Path(source).read_bytes()

for path in Path(closure).read_text().splitlines():
    assert Path(path).exists(), f"SBOM scanner cannot inspect store output: {path}"

with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    target = home / ".config/agents/AGENTS.md"
    env = os.environ | {"HOME": str(home)}

    def activate(*, dry=False, success=True):
        result = subprocess.run(
            [activation], env=env | ({"DRY_RUN": "1"} if dry else {}),
            capture_output=True, text=True,
        )
        assert (result.returncode == 0) == success, (result.stdout, result.stderr)

    activate(dry=True)
    assert not target.parent.exists()
    activate()
    assert target.is_file() and not target.is_symlink()
    assert target.read_bytes() == expected
    assert stat.S_IMODE(target.stat().st_mode) == 0o600

    target.write_text("local edit")
    activate(dry=True)
    assert target.read_text() == "local edit"
    activate()
    assert target.read_bytes() == expected

    for _ in range(2):
        target.write_text("local container edit")
        subprocess.run([entrypoint, command], env=env, check=True)
        assert target.read_bytes() == expected

    original = home / "original"
    original.write_text("leave this file alone")
    original.chmod(0o444)
    target.unlink()
    target.symlink_to(original)
    activate()
    assert not target.is_symlink()
    assert target.read_bytes() == expected
    assert original.read_text() == "leave this file alone"

    target.unlink()
    target.mkdir()
    activate(success=False)
    assert list(target.iterdir()) == []
    assert list(target.parent.glob(".AGENTS.md.*")) == []

print("Agent instructions are writable, reset on activation, and unchanged on dry runs")
