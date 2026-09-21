"""Enforce the curated container's policy on the paths actually shipped."""
import argparse
from collections import Counter, deque
import json
from pathlib import Path
import re
import sys
import tarfile

MIB = 1024 * 1024
NIX_RUNTIME = re.compile(r"nix(?:-(?:cmd|expr|fetchers|flake|main|store|util|nswrapper))?-\d")
LIBRARIES = re.compile(r"(libimagequant|libvpx|qpdf)-\d")


def image_contents(path):
    """Read the finished image's layers without extracting them to disk."""
    with tarfile.open(path) as archive:
        def member(name):
            try:
                return archive.extractfile(name)
            except KeyError:
                return archive.extractfile("./" + name)

        def blob(descriptor):
            return member("blobs/" + descriptor["digest"].replace(":", "/", 1))

        index = json.load(member("index.json"))
        if len(index["manifests"]) != 1:
            raise ValueError("expected one platform image in the OCI archive")
        manifest = json.load(blob(index["manifests"][0]))
        files = {}
        for layer in manifest["layers"]:
            source = blob(layer)
            if layer["mediaType"].endswith(("+zstd", ".zstd")):
                import zstandard
                source = zstandard.ZstdDecompressor().stream_reader(source)
            with source, tarfile.open(fileobj=source, mode="r|*") as content:
                for entry in content:
                    name = entry.name.removeprefix("./").lstrip("/")
                    parts = name.split("/")
                    if len(parts) >= 3 and parts[:2] == ["nix", "store"] and parts[2]:
                        # Nix's hardlink bookkeeping is not a store output.
                        if parts[2] == ".links":
                            continue
                        path = "/" + "/".join(parts[:3])
                        files.setdefault(path, set()).add("/".join(parts[3:]))
        return {"store_layers": [sorted(files)], "files": files}


def package_name(path):
    return Path(path).name[33:]


def dependency_chains(graph):
    incoming = Counter(ref for p, v in graph.items() for ref in v["references"] if ref != p)
    roots = sorted(p for p in graph if not incoming[p])
    parents = dict.fromkeys(roots)
    queue = deque(roots)
    while queue:
        current = queue.popleft()
        for ref in sorted(graph[current]["references"]):
            if ref in graph and ref not in parents:
                parents[ref] = current
                queue.append(ref)

    def chain(path):
        result = [path]
        while parents.get(result[-1]) is not None:
            result.append(parents[result[-1]])
        return list(reversed(result))

    return chain


def largest_paths(report):
    print("Largest shipped store paths (unpacked NAR sizes):", file=sys.stderr)
    for entry in report["largest"]:
        print(f"  {entry['narSize'] / MIB:.1f} MiB: {entry['path']}", file=sys.stderr)
        print("    retained by: " + " -> ".join(entry["chain"]), file=sys.stderr)


def check_closure(config, metadata, policy):
    # Inspect the inventory of the finished image. The metadata supplies
    # sizes and dependency edges, including build-only paths to filter out.
    if config.get("from_image") is not None:
        raise ValueError("size guard requires an image built without fromImage")
    shipped = {p for layer in config["store_layers"] for p in layer}
    if not shipped:
        raise ValueError("image has no store paths; refusing an empty size check")
    available = {entry["path"]: entry for entry in metadata["image"]}
    missing = shipped - available.keys()
    if missing:
        raise ValueError(f"image paths missing from reference graph: {sorted(missing)}")
    graph = {p: available[p] for p in shipped}
    allowed_nix = {entry["path"] for entry in metadata["nixRuntime"]}
    chain = dependency_chains(graph)
    errors = []
    libraries = {}
    for path in sorted(shipped):
        name = package_name(path)
        files = (
            config["files"][path] if "files" in config
            else {str(p.relative_to(path)) for p in Path(path).rglob("*")}
        )
        reasons = []
        if path in policy["forbiddenPaths"]:
            reasons.append("original, untrimmed package returned")
        # Keep Git's documentation outputs; reject its full runtime even
        # when a different nixpkgs revision supplies it.
        if re.match(r"git-\d", name) and "bin/git" in files:
            reasons.append("full Git runtime returned")
        nix_runtime = (
            bool(NIX_RUNTIME.match(name)) and not name.endswith(("-man", "-doc", "-info"))
        ) or (name.startswith("nix-") and any(re.match(r"lib/libnix[^/]*\.so", f) for f in files))
        if nix_runtime and path not in allowed_nix:
            reasons.append("Nix runtime is outside the selected nix.package closure")
        match = LIBRARIES.match(name)
        if match:
            archives = sorted(f for f in files if f.endswith(".a"))
            if archives:
                reasons.append("static archives returned: " + ", ".join(archives))
            if any(re.match(r"lib/[^/]*\.so", f) for f in files):
                libraries.setdefault(match[1], []).append(path)
        for reason in reasons:
            errors.append(reason + ": " + path + "\n  retained by: " + " -> ".join(chain(path)))
    for name, paths in libraries.items():
        if len(paths) > 1:
            for path in paths:
                errors.append(f"duplicate {name} runtime: {path}\n  retained by: " + " -> ".join(chain(path)))

    total = sum(entry["narSize"] for entry in graph.values())
    report = {
        "closureBytes": total,
        "storePathCount": len(shipped),
        "largest": [
            {"path": p, "narSize": graph[p]["narSize"], "chain": chain(p)}
            for p in sorted(graph, key=lambda p: (-graph[p]["narSize"], p))[:10]
        ],
    }
    if total > policy["maxClosureMiB"] * MIB:
        errors.append(f"unpacked closure exceeds {policy['maxClosureMiB']} MiB: {total / MIB:.2f} MiB")
    return report, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    closure = subparsers.add_parser("closure")
    closure.add_argument("--config", required=True, type=Path)
    closure.add_argument("--graph", required=True, type=Path)
    archive = subparsers.add_parser("archive")
    archive.add_argument("archive", type=Path)
    image = subparsers.add_parser("image")
    image.add_argument("archive", type=Path)
    image.add_argument("--graph", required=True, type=Path)
    for command in (closure, archive, image):
        command.add_argument("--policy", required=True, type=Path)
        command.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text())
    if args.mode in ("closure", "image"):
        config = (
            image_contents(args.archive)
            if args.mode == "image" else json.loads(args.config.read_text())
        )
        report, errors = check_closure(
            config, json.loads(args.graph.read_text()), policy
        )
        print(f"Container closure: {report['closureBytes'] / MIB:.2f} MiB "
              f"(limit {policy['maxClosureMiB']} MiB), {report['storePathCount']} paths")
        if errors:
            print("\n".join(errors), file=sys.stderr)
            largest_paths(report)
            return 1
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    if args.mode in ("archive", "image"):
        size = args.archive.stat().st_size
        print(f"Compressed OCI archive: {size / MIB:.2f} MiB (limit {policy['maxArchiveMiB']} MiB)")
        if size > policy["maxArchiveMiB"] * MIB:
            print("Compressed OCI archive exceeds its size budget", file=sys.stderr)
            largest_paths(json.loads(args.report.read_text()))
            return 1
        report = json.loads(args.report.read_text())
        report["archiveBytes"] = size
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
