"""Check the parsed configuration after each merge."""

from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


with tempfile.TemporaryDirectory() as temporary:
    target = Path(temporary) / "config.toml"
    cases = [
        (None, {"machine": {"homeMount": "none"}}),
        (
            '# user comment\n[machine]\nfoo = "bar"\n\n[network]\nx = 1\n',
            {"machine": {"foo": "bar", "homeMount": "none"}, "network": {"x": 1}},
        ),
        ('[machine]\nhomeMount = "all"\n', {"machine": {"homeMount": "none"}}),
    ]
    for original, expected in cases:
        if original is not None:
            target.write_text(original)
        subprocess.run([sys.executable, sys.argv[1], target], check=True)
        actual = target.read_text()
        assert tomllib.loads(actual) == expected, actual
        if original and "# user comment" in original:
            assert "# user comment\n" in actual, actual
        before = target.read_bytes()
        subprocess.run([sys.executable, sys.argv[1], target], check=True)
        assert target.read_bytes() == before
