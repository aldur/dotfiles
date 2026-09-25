import argparse
import hashlib
import os
import stat
import sys
import tempfile
from collections.abc import MutableMapping
from pathlib import Path

import tomlkit


def merge(existing: MutableMapping, managed: MutableMapping) -> None:
    for key, value in managed.items():
        current = existing.get(key)
        if isinstance(current, MutableMapping) and isinstance(value, MutableMapping):
            merge(current, value)
        else:
            existing[key] = value


def atomic_write(target: Path, content: str, *, replace: bool = True) -> None:
    fd, temporary_name = tempfile.mkstemp(dir=target.parent, prefix=".config.toml.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            temporary.write(content)
        os.chmod(temporary_name, stat.S_IRUSR | stat.S_IWUSR)
        if replace:
            os.replace(temporary_name, target)
        else:
            # Publish a complete profile only if absent. Concurrent launches
            # and later settings saved by Codex must never be overwritten.
            try:
                os.link(temporary_name, target)
            except FileExistsError:
                pass
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def yolo(command: list[str]) -> None:
    # A named profile can supply trust without changing shared user settings.
    # Remove only the selected profile; forward all other arguments unchanged.
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("-p", "--profile")
    profile, remaining = parser.parse_known_args(command[1:])
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("-C", "--cd")
    parser.add_argument("-h", "--help", "-V", "--version", action="store_true")
    args, _ = parser.parse_known_args(remaining)
    if args.help:
        os.execvp(command[0], command)

    workspace = Path(args.cd or os.getcwd()).resolve(strict=True)
    if not workspace.is_dir():
        raise ValueError(f"not a workspace directory: {workspace}")
    codex_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))).absolute()
    user_config = codex_home / "config.toml"
    user = tomlkit.loads(user_config.read_text()) if user_config.exists() else {}
    selected = profile.profile or user.get("profile")
    document = (tomlkit.loads((codex_home / f"{selected}.config.toml").read_text())
                if selected else tomlkit.document())
    document.setdefault("projects", {}).setdefault(str(workspace), {})["trust_level"] = "trusted"
    content = tomlkit.dumps(document)
    # Content-addressed profiles let concurrent launches safely share identical
    # settings, while different workspaces/profiles never overwrite each other.
    name = "codex-yolo-" + hashlib.sha256(content.encode()).hexdigest()
    target = codex_home / f"{name}.config.toml"
    codex_home.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        atomic_write(target, content, replace=False)
    os.execvp(command[0], [command[0], "--profile", name, *remaining])


def main() -> None:
    if sys.argv[1] == "--yolo":
        yolo(sys.argv[2:])
        return
    managed_path, target_path = map(Path, sys.argv[1:])
    managed = tomlkit.loads(managed_path.read_text())
    existing = tomlkit.loads(target_path.read_text()) if target_path.exists() else tomlkit.document()
    merge(existing, managed)
    atomic_write(target_path, tomlkit.dumps(existing))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"codex-config: {error}", file=sys.stderr)
        sys.exit(1)
