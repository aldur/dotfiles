"""Check concurrent installation, retry, prefetch, and cached browser launches."""

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import sys

package = Path(sys.argv[1])
log = Path("installs.log").resolve()
state = Path("state").resolve()
env = dict(os.environ, PLAYWRIGHT_BROWSER_STATE_DIR=str(state), LAZY_TEST_LOG=str(log))


def launch(*args, **overrides):
    return subprocess.run(
        [package / "bin/playwright-browser", *args],
        env=env | overrides, capture_output=True, text=True, timeout=15,
    )


with ThreadPoolExecutor(2) as pool:
    results = list(pool.map(lambda _: launch("--version"), range(2)))
assert all(r.returncode == 0 and r.stdout == "browser:--version\n" for r in results), results
assert log.read_text().splitlines() == ["install"], "concurrent workers installed twice"

cached = launch("--version", LAZY_TEST_FAIL="1")
assert cached.returncode == 0 and cached.stderr == "", cached
prefetch = subprocess.run(
    [package / "bin/playwright-browser-prefetch"],
    env=env, capture_output=True, text=True, check=True, timeout=15,
)
assert Path(prefetch.stdout.strip()).is_file(), prefetch
assert log.read_text().splitlines() == ["install"], "cached launch installed again"

retry_state = str(Path("retry-state").resolve())
failed = launch("--version", PLAYWRIGHT_BROWSER_STATE_DIR=retry_state, LAZY_TEST_FAIL="1")
assert failed.returncode != 0 and "Chromium installation failed" in failed.stderr, failed
assert not failed.stdout, failed
retry = launch("--version", PLAYWRIGHT_BROWSER_STATE_DIR=retry_state)
assert retry.returncode == 0 and retry.stdout == "browser:--version\n", retry
assert log.read_text().splitlines() == ["install"] * 3
print("Lazy browser: concurrent install, cached launch, prefetch, and retry passed")
