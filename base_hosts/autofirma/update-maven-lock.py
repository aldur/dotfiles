#!/usr/bin/env python3
"""Lock three populated Maven repositories produced by autofirma-nix."""

import argparse
import base64
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True,
                        help="autofirma-nix checkout containing flake.lock")
    parser.add_argument("--maven-version", required=True)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).with_name("maven-lock.json"))
    parser.add_argument("jmulticard", type=Path)
    parser.add_argument("clienteafirma_external", type=Path)
    parser.add_argument("autofirma", type=Path)
    args = parser.parse_args()

    upstream = json.loads((args.upstream / "flake.lock").read_text())
    source_names = ("jmulticard-src", "clienteafirma-external-src", "autofirma-src")
    lock = {
        "mavenVersion": args.maven_version,
        "sources": {name: upstream["nodes"][name]["locked"]["rev"]
                    for name in source_names},
        "artifacts": {},
        "metadata": {},
        "repositories": {},
    }

    for name, directory in (
        ("jmulticard", args.jmulticard),
        ("clienteafirma-external", args.clienteafirma_external),
        ("autofirma", args.autofirma),
    ):
        root = directory / ".m2" / "repository"
        if not root.is_dir():
            parser.error(f"missing Maven repository: {root}")
        paths = []
        for file in sorted(root.rglob("*")):
            if not file.is_file():
                continue
            path = file.relative_to(root).as_posix()
            # Nix verifies SHA-256; Maven's SHA-1 sidecars are unnecessary
            # for the offline build. Do not lock local resolver state.
            if file.suffix == ".sha1":
                continue
            if "SNAPSHOT" in path:
                parser.error(f"snapshot dependency needs a release pin: {path}")
            if file.name == "maven-metadata-central.xml":
                entries, value = lock["metadata"], file.read_text()
            elif file.suffix in (".jar", ".pom"):
                digest = hashlib.sha256(file.read_bytes()).digest()
                entries = lock["artifacts"]
                value = "sha256-" + base64.b64encode(digest).decode()
            else:
                parser.error(f"unexpected repository file: {path}")
            if path in entries and entries[path] != value:
                parser.error(f"repositories disagree on {path}")
            entries[path] = value
            paths.append(path)
        lock["repositories"][f"{name}-dependencies"] = paths

    args.output.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
    print(f"Locked {len(lock['artifacts'])} artifacts and "
          f"{len(lock['metadata'])} metadata files in {args.output}")


if __name__ == "__main__":
    main()
