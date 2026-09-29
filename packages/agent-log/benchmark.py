"""Fresh-process benchmarks; no transcript contents are written to files.

Run from the project being measured, or pass --project. Before/after runs are
interleaved. These measure CLI work, including process startup and output, not
terminal drawing. The operating system's normal filesystem cache is not cleared.
"""

import argparse
import os
from pathlib import Path
import shutil
import secrets
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda p: str(Path(p).resolve()))
    parser.add_argument("--baseline", default=shutil.which("agent-log"))
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--min-speedup", type=float, default=0,
                        help="fail unless BOTH session listings achieve this factor")
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    if not args.baseline:
        parser.error("pass the original executable with --baseline")
    args.baseline = str(Path(args.baseline).resolve())
    if args.binary == args.baseline:
        parser.error("baseline and candidate must be different executables")
    with tempfile.TemporaryDirectory(prefix="agent-log-bench-") as temporary:
        root = Path(temporary)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, NO_COLOR="1", XDG_CACHE_HOME=str(root / "cache"),
                   XDG_RUNTIME_DIR=str(runtime))

        def run(binary, flags, capture=False):
            return subprocess.run([binary, *flags], cwd=args.project, env=env,
                                  stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                                  check=True, text=capture).stdout

        def compare(label, flags):
            samples = {args.baseline: [], args.binary: []}
            for repeat in range(args.runs):
                order = list(samples)
                if repeat % 2:
                    order.reverse()
                for binary in order:
                    start = time.perf_counter()
                    run(binary, flags)
                    samples[binary].append(1000 * (time.perf_counter() - start))
            before, after = (statistics.median(samples[b]) for b in samples)
            print(f"{label}: {before:.1f} -> {after:.1f} ms; "
                  f"{after - before:+.1f} ms ({100 * (after / before - 1):+.1f}%); "
                  f"{before / after:.2f}x faster", flush=True)
            return before / after

        speedups = [compare("Project listing", ["--list"]),
                    compare("All-project listing", ["--all", "--list"])]

        # Compare coverage/metadata without printing or persisting any text.
        def inventory(binary):
            return {parts[1]: (parts[0], parts[3])
                    for row in run(binary, ["--all", "--list"], True).splitlines()
                    if len(parts := row.split("\t")) >= 4}

        before, after = inventory(args.baseline), inventory(args.binary)
        print(f"Sessions: {len(before)} before, {len(after)} after; "
              f"missing={len(before.keys() - after.keys())}, "
              f"added={len(after.keys() - before.keys())}, "
              f"changed labels/IDs={sum(before[p] != after[p] for p in before.keys() & after.keys())}",
              flush=True)
        assert not before.keys() - after.keys(), "candidate lost sessions"

        if after:
            largest = max(after, key=lambda p: Path(p).stat().st_size)
            turns = run(args.binary, ["--list", largest], True).splitlines()
            if turns:
                key = turns[-1].split("\t")[0]
                compare("Large-log turn preview", ["_show", key, largest, "--color=never"])
                compare("Large-log turn listing", ["--list", largest])

        # A fixed "unlikely" word can occur in the very agent transcript
        # describing this benchmark. Generate the no-match term at runtime.
        needle = "agentlog-benchmark-" + secrets.token_hex(16)
        for label, flags in [("Project search", []), ("All-project search", ["--all"])]:
            samples = []
            for _ in range(args.runs):
                start = time.perf_counter()
                output = run(args.binary, [*flags, "--list", "--query", needle], True)
                samples.append(1000 * (time.perf_counter() - start))
                assert not output, "the no-match benchmark term unexpectedly matched"
            print(f"{label} (no-match full scan): {statistics.median(samples):.1f} ms", flush=True)
        assert not (root / "cache").exists(), "unexpected cache"
        assert not list(runtime.iterdir()), "unexpected runtime files"
        print("No cache or runtime files created.")
        if args.min_speedup and min(speedups) < args.min_speedup:
            raise SystemExit(f"FAILED: both listings must be >= {args.min_speedup:g}x faster")


if __name__ == "__main__":
    main()
