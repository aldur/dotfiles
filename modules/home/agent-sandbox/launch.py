"""Host-side mount policy and lifecycle; the public CLI remains the argc script."""

import argparse
import ctypes
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys


DIRECTORIES = (".git",)
FILES = (".lazygit.yml",)
INSTRUCTION_FILES = ("AGENTS.md", "CLAUDE.md", "CLAUDE.local.md")
# The sandbox shares the host state of the agent, in both directions:
# sessions, settings, hooks, MCP servers and credentials. The host runs
# what a sandboxed agent writes here.
AGENT_STATE = {
    "codex": (".codex",),
    "claude": (".claude", ".claude.json"),
}


def fail(message):
    raise RuntimeError(message)


def within(path, root):
    return path == root or root in path.parents


def identity(path):
    info = path.lstat()
    return [info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode)]


def directory(path):
    """Never follow an entry left by a previous sandbox when creating state."""
    if not path.parent.exists():
        directory(path.parent)
    if path.parent.resolve() != path.parent:
        fail(f"state directory crosses a symlink: {path}")
    path.mkdir(mode=0o700, exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        fail(f"expected a real state directory: {path}")
    return path


class Reservations:
    """Short registry locks, shared ownership, inode-checked empty-only cleanup.

    SIGKILL cannot run cleanup; a subsequent launch reaps dead owners. A host
    edit/replacement is left alone. No lock is held for the command's lifetime.
    """

    def __init__(self):
        self.root = directory(Path(f"/tmp/agent-sandbox-reservations-{os.getuid()}"))
        info = self.root.stat()
        if info.st_uid != os.getuid() or info.st_mode & 0o077:
            fail("unsafe reservation registry permissions")
        self.owner = f"{os.getpid()}:{self.start(os.getpid())}"

    @staticmethod
    def start(pid):
        try:
            return Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[19]
        except FileNotFoundError:
            return None

    @contextmanager
    def locked(self):
        fd = os.open(self.root / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            registry = self.root / "paths.json"
            records = json.loads(registry.read_text()) if registry.exists() else {}
            try:
                yield records
            finally:
                temporary = self.root / "paths.new"
                temporary.write_text(json.dumps(records))
                temporary.replace(registry)

    def reap(self, records, exiting=False):
        for name, record in list(records.items()):
            record["owners"] = [
                owner for owner in record["owners"]
                if (not exiting or owner != self.owner)
                and self.start(owner.split(":")[0]) == owner.split(":")[1]
            ]
            if record["owners"]:
                continue
            path = Path(record["path"])
            try:
                if identity(path) == record["identity"]:
                    if path.is_dir():
                        path.rmdir()
                    elif path.stat().st_size == 0:
                        path.unlink()
            except OSError:
                # Nonempty entries, renamed parents and host edits are retained.
                pass
            del records[name]

    def prepare(self, paths):
        with self.locked() as records:
            self.reap(records)
            for path, is_dir in paths.items():
                parent = path.parent.stat()
                # Bind-mounted /persist aliases must share ownership too.
                key = f"{parent.st_dev}:{parent.st_ino}:{path.name}"
                if not path.exists() and not path.is_symlink():
                    try:
                        if is_dir:
                            path.mkdir(mode=0o700)
                        else:
                            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                            os.close(fd)
                    except FileExistsError:
                        pass
                    else:
                        records[key] = {"path": str(path), "identity": identity(path), "owners": []}
                if key in records and identity(path) == records[key]["identity"]:
                    if self.owner not in records[key]["owners"]:
                        records[key]["owners"].append(self.owner)

    def close(self):
        with self.locked() as records:
            self.reap(records, exiting=True)


class Policy:
    def __init__(self, home, git_write):
        self.home = home
        self.git_write = git_write
        self.fds = []
        self.shared_sources = set()
        self.direnv_roots = {
            (home / ".local/share/direnv").resolve(),
            (Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") / "direnv").resolve(),
        }
        self.shared_sources.update(root for root in self.direnv_roots if root.is_dir())
        self.reservations = Reservations()

    def bind(self, source, destination, readonly=True):
        # Pin the source object rather than let bwrap resolve it a second time.
        if source.resolve(strict=True) != source:
            fail(f"mount source changed to a symlink: {source}")
        fd = os.open(source, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC)
        if stat.S_ISLNK(os.fstat(fd).st_mode):
            os.close(fd)
            fail(f"mount source changed to a symlink: {source}")
        self.fds.append(fd)
        return ["--ro-bind-fd" if readonly else "--bind-fd", str(fd), str(destination)]

    def agent_state(self, kind):
        """Mount the host state of the selected agent, writable."""
        mounts = []
        for name in AGENT_STATE.get(kind, ()):
            path = self.home / name
            if name == ".claude.json" and not path.exists():
                # Claude creates this file on the first run. A mount needs it.
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                os.write(fd, b"{}\n")
                os.close(fd)
            if not path.exists():
                fail(f"initialize {kind} outside the sandbox first: {path}")
            source = path.resolve(strict=True)
            if source in (self.home, Path("/")):
                fail(f"refusing broad agent state: {path}")
            mounts += self.bind(source, path, readonly=False)
        return mounts

    def metadata(self, writable, readonly):
        names = tuple(name for name in DIRECTORIES + FILES if name != ".git" or not self.git_write)
        protected = {}
        git_dirs = set()
        hardlinks = {}

        def walk_error(error):
            raise error

        def remember_hardlink(path, direct_grant=False):
            info = path.lstat()
            if stat.S_ISREG(info.st_mode) and (info.st_nlink > 1 or direct_grant):
                hardlinks.setdefault((info.st_dev, info.st_ino), set()).add(path)

        def git_pointer(path):
            if not path.is_file():
                return
            line = path.read_text().strip()
            if not line.startswith("gitdir: "):
                fail(f"invalid Git directory pointer: {path}")
            git_dir = (path.parent / line[8:]).resolve(strict=True)
            candidates = {git_dir}
            common = git_dir / "commondir"
            if common.exists():
                candidates.add((git_dir / common.read_text().strip()).resolve(strict=True))
            for target in candidates:
                if within(self.home.resolve(), target) or target in (Path("/tmp"), Path("/run"), Path("/persist")):
                    fail(f"refusing broad Git directory pointer: {path}")
                if not target.is_dir() or not (target / "HEAD").is_file():
                    fail(f"invalid external Git directory: {target}")
                git_dirs.add(target)

        def protect(path, reserve=False):
            if path.is_symlink() or path.resolve().parent != path.parent:
                fail(f"protected metadata crosses a symlink: {path}")
            if path.exists() or reserve:
                protected[path] = path.name in DIRECTORIES
            if path.is_file() and path.stat().st_nlink != 1:
                fail(f"protected metadata has hard links: {path}")
            if path.name == ".git":
                git_pointer(path)

        for source, destination in writable:
            for root in self.direnv_roots:
                if (within(source, root) or within(root, source)
                    or (root.exists() and any(os.path.samefile(parent, root)
                                             for parent in (source, *source.parents)))):
                    fail(f"cannot grant host direnv approvals or caches: {destination}")
            managed = self.reservations.root
            if within(source, managed) or within(managed, source):
                fail(f"cannot grant sandbox lifecycle state: {destination}")
            # Explicit grants cannot make agent configuration writable through
            # another spelling. Its state must use the selected profile.
            for root in (self.home / ".codex", self.home / ".claude", self.home / ".claude.json"):
                # Preservation bind mounts can name the same tree under /persist
                # without any symlink for realpath to resolve.
                same_tree = root.exists() and any(
                    ancestor.exists() and os.path.samefile(ancestor, root)
                    for ancestor in (source, *source.parents)
                )
                if within(source, root.resolve()) or same_tree:
                    fail(f"agent state must use --profile, not a writable grant: {destination}")
            if not source.is_dir():
                remember_hardlink(source, direct_grant=True)
                if source.name in names:
                    protect(source)
                continue
            for name in names:
                protect(source / name, reserve=True)
            # Discover existing nested repositories/instructions without following
            # symlinks or descending into the metadata we are about to protect.
            for directory_name, dirs, files in os.walk(source, followlinks=False, onerror=walk_error):
                parent = Path(directory_name)
                if any(root.exists() and os.path.samefile(parent, root) for root in self.direnv_roots):
                    fail(f"writable grant includes host direnv state: {destination}")
                for name in files:
                    remember_hardlink(parent / name)
                for name in names:
                    if name in dirs or name in files:
                        protect(parent / name)
                if ".git" in dirs or ".git" in files:
                    git_pointer(parent / ".git")
                    for name in names:
                        protect(parent / name, reserve=True)
                dirs[:] = [name for name in dirs if name not in DIRECTORIES]
            # A command launched in a subdirectory still needs the parent's Git
            # metadata and instructions, but not the rest of its working tree.
            for parent in source.parents:
                if parent == self.home or parent == Path("/"):
                    break
                if (parent / ".git").exists():
                    for name in names:
                        protect(parent / name)
                    # Keep parent instructions readable when launching below
                    # the repository root. They follow ordinary write grants;
                    # instruction files inside a grant need no special mounts.
                    for name in INSTRUCTION_FILES:
                        path = parent / name
                        if path.is_file() and not any(
                            within(path.resolve(), root) for root, _ in writable
                        ):
                            readonly.append((path.resolve(strict=True), path))
                    if self.git_write:
                        if (parent / ".git").is_file():
                            git_pointer(parent / ".git")
                        else:
                            git_dirs.add((parent / ".git").resolve())
                    break

        self.reservations.prepare(protected)
        # Explicit read-only sources are protected through admitted aliases too.
        restrictions = set(protected) | self.shared_sources | {source for source, _ in readonly}
        if not self.git_write:
            restrictions |= git_dirs
        for root in list(restrictions):
            if root.is_dir():
                for source, _ in writable:
                    if any(os.path.samefile(parent, root) for parent in (source, *source.parents)):
                        restrictions.add(source)
        # A pre-existing hard link in an ordinary writable directory names the
        # same inode as protected metadata. Protect each admitted spelling too.
        # New links across the resulting mount boundary are rejected by Linux.
        if hardlinks:
            for root in list(restrictions):
                if root.is_dir():
                    entries = (
                        Path(parent) / name
                        for parent, _, files in os.walk(root, followlinks=False, onerror=walk_error)
                        for name in files
                    )
                else:
                    entries = (root,)
                for path in entries:
                    info = path.lstat()
                    restrictions.update(hardlinks.get((info.st_dev, info.st_ino), ()))
        mounts = []
        if self.git_write:
            for source in sorted(git_dirs):
                mounts += self.bind(source, source, readonly=False)
        destinations = set()
        for source in sorted(restrictions, key=lambda path: len(path.parts)):
            targets = {source} if source in protected or source in git_dirs else set()
            for root, destination in writable:
                if within(source, root):
                    targets.add(destination / source.relative_to(root))
                elif within(root, source):
                    mounts += self.bind(root, destination)
            for target in sorted(targets):
                if target not in destinations:
                    mounts += self.bind(source, target)
                    destinations.add(target)
        for source, destination in readonly:
            mounts += self.bind(source, destination)
        return mounts

    def close(self):
        self.reservations.close()
        for fd in self.fds:
            os.close(fd)


def main():
    parent = os.getppid()
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", required=True, type=Path)
    parser.add_argument("--state-kind", choices=("", "codex", "claude"), required=True)
    parser.add_argument("--git-write", choices=("0", "1"), required=True)
    parser.add_argument("--writable", nargs=2, action="append", default=[])
    parser.add_argument("--readonly", nargs=2, action="append", default=[])
    options, command = parser.parse_known_args()
    command = command[1:]
    separator = command.index("--")
    mounts, child = command[:separator], command[separator:]
    writable = [tuple(map(Path, pair)) for pair in options.writable]
    readonly = [tuple(map(Path, pair)) for pair in options.readonly]
    if options.git_write == "1":
        print("agent-sandbox: WARNING: --git-write permits repository metadata, hooks and configuration writes.", file=sys.stderr)
    policy = Policy(options.home, options.git_write == "1")
    process = None

    def interrupted(signum, _frame):
        if process is not None and process.poll() is None:
            process.send_signal(signum)
        raise SystemExit(128 + signum)

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        # Keep bwrap's die-with-parent guarantee across this supervisor.
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "cannot set parent death signal")
        if os.getppid() != parent:
            interrupted(signal.SIGTERM, None)
        writable_mounts = []
        pinned = []
        for source, destination in writable:
            writable_mounts += policy.bind(source, destination, readonly=False)
            info = os.fstat(policy.fds[-1])
            pinned.append((source, info.st_dev, info.st_ino))
        state = policy.agent_state(options.state_kind)
        protections = policy.metadata(writable, readonly)
        for source, device, inode in pinned:
            if identity(source)[:2] != [device, inode]:
                fail(f"writable grant changed during setup: {source}")
        index = mounts.index("--sandbox-writable")
        mounts[index:index + 1] = writable_mounts
        index = mounts.index("--sandbox-state")
        mounts[index:index + 1] = state
        process = subprocess.Popen(mounts + protections + child, pass_fds=(3, *policy.fds))
        result = process.wait()
        return result if result >= 0 else 128 - result
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        policy.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"agent-sandbox: {error}", file=sys.stderr)
        sys.exit(1)
