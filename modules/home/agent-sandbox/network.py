"""Supervise pasta and provide DNS inside its network namespace."""

import argparse
import ctypes
import ipaddress
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


PR_SET_PDEATHSIG = 1
PR_SET_CHILD_SUBREAPER = 36


def resolver(text):
    addresses = {4: "169.254.1.53", 6: "fd00::53"}
    seen, lines, args = set(), [], []
    for line in text.splitlines():
        fields = line.split()
        if fields[:1] != ["nameserver"]:
            lines.append(line)
            continue
        if len(fields) < 2:
            continue
        version = ipaddress.ip_address(fields[1]).version
        if version not in seen:
            seen.add(version)
            address = addresses[version]
            lines.append(f"nameserver {address}")
            args += ["--dns-forward", address, "--dns-host", fields[1]]
    return "\n".join(lines) + "\n", args


def children():
    """The children of this process, also adopted ones: it is a subreaper.

    /proc/PID/task/TID/children needs CONFIG_PROC_CHILDREN, which some kernels
    (for example ChromeOS) do not have. Read the parent of each process.
    """
    found = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            stat = Path(entry.path, "stat").read_text()
        except OSError:
            continue
        # The command name can contain spaces and ")": the state and the
        # parent come after its last ")".
        if int(stat[stat.rindex(")") + 2:].split()[1]) == os.getpid():
            found.append(int(entry.name))
    return found


def cleanup():
    # Reap descendants too, including helpers left by a failed setup.
    deadline = time.monotonic() + 3
    while children():
        signum = signal.SIGTERM if time.monotonic() < deadline else signal.SIGKILL
        for pid in children():
            try:
                os.kill(pid, signum)
            except ProcessLookupError:
                pass
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            return
        time.sleep(0.02)


def main():
    parent = os.getppid()
    parser = argparse.ArgumentParser()
    parser.add_argument("--pasta")
    parser.add_argument("--bwrap")
    parser.add_argument("--wait-dir", type=Path)
    parser.add_argument("--seccomp", required=True)
    options, command = parser.parse_known_args()
    command = command[1:]

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, interrupted)
    libc = ctypes.CDLL(None, use_errno=True)
    for option, value in ((PR_SET_PDEATHSIG, signal.SIGTERM), (PR_SET_CHILD_SUBREAPER, 1)):
        if libc.prctl(option, value, 0, 0, 0):
            raise OSError(ctypes.get_errno(), "cannot supervise private network")
    if os.getppid() != parent:
        return 143

    if options.wait_dir is not None:
        # This is still the trusted launcher, before the filesystem sandbox.
        # Keep the host PID namespace so shared reservation records stay valid.
        ready = options.wait_dir / "ready.new"
        ready.write_text(str(os.getpid()))
        ready.replace(options.wait_dir / "ready")
        deadline = time.monotonic() + 15
        while not (options.wait_dir / "go").exists():
            if time.monotonic() >= deadline:
                raise RuntimeError("private network setup timed out")
            time.sleep(0.02)
        fd = os.open(options.seccomp, os.O_RDONLY)
        os.dup2(fd, 3, inheritable=True)
        os.set_inheritable(3, True)
        if fd != 3:
            os.close(fd)
        os.execv(command[0], command)

    if not options.pasta or not options.bwrap:
        parser.error("--pasta and --bwrap are required")

    with tempfile.TemporaryDirectory(prefix="agent-sandbox-network-") as directory:
        directory = Path(directory)
        path = directory / "resolv.conf"
        host = Path("/etc/resolv.conf")
        text, dns = resolver(host.read_text() if host.exists() else "")
        path.write_text(text)
        index = command.index("--")
        command[index:index] = ["--resolv-conf", str(path)]
        try:
            # The first bubblewrap only creates the network namespace. The
            # trusted launcher then builds the normal empty-root sandbox.
            process = subprocess.Popen([
                options.bwrap, "--die-with-parent", "--unshare-user", "--unshare-net",
                "--bind", "/", "/", "--", sys.executable, "-I", __file__,
                "--wait-dir", str(directory), "--seccomp", options.seccomp, "--", *command,
            ])

            def wait_file(path, children):
                deadline = time.monotonic() + 15
                while not path.exists():
                    if any(child.poll() is not None for child in children):
                        raise RuntimeError("private network setup failed")
                    if time.monotonic() >= deadline:
                        raise RuntimeError("private network setup timed out")
                    time.sleep(0.02)

            wait_file(directory / "ready", [process])
            pid = int((directory / "ready").read_text())
            pasta = subprocess.Popen([
                options.pasta, "--foreground", "--config-net", "--quiet", "--no-map-gw",
                "-t", "none", "-u", "none", "-T", "none", "-U", "none", *dns,
                "--pid", str(directory / "pasta.pid"),
                "--userns", f"/proc/{pid}/ns/user", "--netns", f"/proc/{pid}/ns/net",
            ])
            wait_file(directory / "pasta.pid", [process, pasta])
            (directory / "go").touch()
            while process.poll() is None:
                if pasta.poll() is not None:
                    raise RuntimeError("private network helper stopped")
                time.sleep(0.02)
            result = process.returncode
            return result if result >= 0 else 128 - result
        finally:
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                signal.signal(signum, signal.SIG_IGN)
            cleanup()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"agent-sandbox: {error}", file=sys.stderr)
        sys.exit(1)
