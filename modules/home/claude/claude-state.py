"""Checked host-side I/O for Claude's sandbox-writable state.

HOME is the host-selected trust anchor. Never follow entries below it. JSON
updates preserve the inode because preservation can bind-mount these files.
No predictable temporary files or pathname-based chmod/truncation are used.
"""

import argparse
from contextlib import ExitStack, contextmanager
import os
import stat
import subprocess
import sys


def validate(fd, directory=False, *, path="state file"):
    info = os.fstat(fd)
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    if not kind(info.st_mode):
        raise ValueError(f"unsafe state: {path}: expected a {'directory' if directory else 'regular file'}")
    if info.st_uid != os.getuid():
        raise ValueError(f"unsafe state: {path}: owned by UID {info.st_uid}, expected {os.getuid()}")
    if not directory and info.st_nlink != 1:
        raise ValueError(f"unsafe state: {path}: expected one hard link, found {info.st_nlink}")
    if info.st_mode & 0o022:
        raise ValueError(
            f"unsafe state: {path}: group/other-writable mode {stat.S_IMODE(info.st_mode):04o}; "
            "review existing state and remove group/other write access before retrying"
        )


@contextmanager
def state_file(home, target, *, write=False, create=False):
    with ExitStack() as stack:
        def opened(path, flags, parent=None):
            fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=parent)
            stack.callback(os.close, fd)
            return fd

        parent = opened(home, os.O_RDONLY | os.O_DIRECTORY)
        path = os.fspath(home)
        validate(parent, directory=True, path=path)
        parts = target.split("/")
        for part in parts[:-1]:
            if part in ("", ".", ".."):
                raise ValueError("invalid state directory")
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=parent)
                except FileExistsError:
                    pass
            parent = opened(part, os.O_RDONLY | os.O_DIRECTORY, parent)
            path = os.path.join(path, part)
            validate(parent, directory=True, path=path)
        if parts[-1] in ("", ".", ".."):
            raise ValueError("invalid state filename")
        flags = (os.O_RDWR if write else os.O_RDONLY) | os.O_NONBLOCK
        try:
            fd = opened(parts[-1], flags, parent)
        except FileNotFoundError:
            if not create:
                raise
            fd = opened(parts[-1], flags | os.O_CREAT | os.O_EXCL, parent)
        validate(fd, path=os.path.join(path, parts[-1]))
        yield fd


def read(fd):
    with os.fdopen(os.dup(fd), "rb") as stream:
        return stream.read()


def write(fd, content):
    # Recheck after the transformation, before any chmod or content mutation.
    validate(fd)
    os.fchmod(fd, 0o600)
    os.lseek(fd, 0, os.SEEK_SET)
    with os.fdopen(os.dup(fd), "wb") as stream:
        stream.write(content)
        stream.flush()
        stream.truncate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", required=True)
    parser.add_argument("--skip-empty", action="store_true")
    parser.add_argument("operation", choices=("read", "write", "update"))
    parser.add_argument("target", choices=(".claude/yolo-refresh", ".claude/settings.json", ".claude.json"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    writing = args.operation != "read"
    with ExitStack() as stack:
        try:
            fd = stack.enter_context(state_file(args.home, args.target, write=writing,
                                                create=writing and not args.skip_empty))
        except FileNotFoundError:
            if writing and not args.skip_empty:
                raise
            return
        if args.operation == "read":
            sys.stdout.buffer.write(read(fd))
        elif args.operation == "write":
            write(fd, sys.stdin.buffer.read())
        else:
            original = read(fd)
            if args.skip_empty and not original:
                return
            result = subprocess.run(args.command, input=original or b"{}",
                                    stdout=subprocess.PIPE, check=True)
            write(fd, result.stdout)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"claude-state: {error}", file=sys.stderr)
        sys.exit(1)
