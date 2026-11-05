"""Install and launch the pinned browser through the real Nix client."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


launcher, expected_browser = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix="playwright-install-") as temporary:
    home = Path(temporary)
    state = home / "browser-state"
    env = os.environ | {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "PLAYWRIGHT_BROWSER_STATE_DIR": str(state),
    }
    result = subprocess.run(
        [launcher / "bin/playwright-browser", "--version"],
        env=env, capture_output=True, text=True, timeout=600,
    )
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert result.stdout.strip(), result
    roots = list(state.glob("*/browser"))
    assert len(roots) == 1, roots
    assert roots[0].is_symlink() and roots[0].resolve() == expected_browser, roots
    prefetched = subprocess.run(
        [launcher / "bin/playwright-browser-prefetch"],
        env=env, capture_output=True, text=True, check=True, timeout=30,
    )
    executable = Path(prefetched.stdout.strip())
    assert executable.is_file() and executable.resolve().is_relative_to(expected_browser), executable
    print(result.stdout.strip())
    print("Pinned browser installed and launched from an empty browser state.")
