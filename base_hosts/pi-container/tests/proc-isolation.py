"""Check inherited procfs using an outer process with the same Unix UID."""
import errno
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def probe(pid, fd, outer_pid, secret):
    status = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines())
    assert status["NoNewPrivs"].strip() == "1"
    assert status["Seccomp"].strip() == "2"
    assert all(int(status[name], 16) == 0 for name in ("CapEff", "CapPrm", "CapBnd", "CapAmb"))
    # The existing procfs reports outer PID IDs; getpid still belongs to the
    # private PID namespace. Its public process listing is intentionally shared.
    assert int(os.readlink("/proc/self")) != os.getpid()
    assert len(status["NSpid"].split()) >= 2
    assert Path(f"/proc/{pid}/status").exists()
    try:
        os.kill(int(outer_pid), 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError("outer PID reachable through the private PID namespace")
    for path in (
        f"/proc/{pid}/root/tmp", f"/proc/{pid}/cwd",
        f"/proc/{pid}/environ", f"/proc/{pid}/fd/{fd}",
        f"/proc/{pid}/ns/user", f"/proc/{pid}/mem",
    ):
        try:
            with open(path, "rb") as stream:
                stream.read(32)
        except OSError as error:
            assert error.errno in (errno.EACCES, errno.EPERM), (path, error)
        else:
            raise AssertionError(f"outer process accessible: {path}")
    # Check every visible process, including bubblewrap's setup/supervisor
    # processes, for a root that could bypass the filesystem allowlist.
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            (process / "root" / secret.lstrip("/")).read_bytes()
        except OSError as error:
            assert error.errno in (errno.ENOENT, errno.EACCES, errno.EPERM, errno.ESRCH), (process, error)
        else:
            raise AssertionError(f"outer file reachable through {process}/root")
    # Neither procfs nor the Git metadata can be written through the bind.
    for path in ("/proc/sys/kernel/hostname", ".git/config"):
        try:
            with open(path, "w"):
                pass
        except OSError as error:
            assert error.errno in (errno.EROFS, errno.EACCES, errno.EPERM), (path, error)
        else:
            raise AssertionError(f"protected path writable: {path}")
    Path("result").write_text("sandboxed")


def main():
    if len(sys.argv) > 1:
        probe(*sys.argv[1:])
        return
    assert os.getuid() != 0
    wrapper = next(Path("/nix/store").glob("*-agent-sandbox/bin/agent-sandbox"))
    with tempfile.TemporaryDirectory() as directory:
        base = Path(directory)
        workspace = base / "workspace"
        (workspace / ".git").mkdir(parents=True)
        (workspace / ".git/config").write_text("fixture\n")
        secret = base / "secret"
        secret.write_text("fixture-secret")
        outer = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
        try:
            assert outer.pid > 2
            with secret.open() as stream:
                command = [str(wrapper), "--profile", "pi", "--workspace", str(workspace)]
                script = Path(__file__).resolve()
                if not script.is_relative_to("/nix/store"):
                    command += ["--ro", str(script)]
                subprocess.run([
                    *command, "--", sys.executable, str(script),
                    str(os.getpid()), str(stream.fileno()), str(outer.pid), str(secret),
                ], check=True)
            assert outer.poll() is None
        finally:
            outer.terminate()
            outer.wait(timeout=10)
        assert (workspace / "result").read_text() == "sandboxed"
        assert (workspace / ".git/config").read_text() == "fixture\n"
        assert secret.read_text() == "fixture-secret"
    print("passed: inherited procfs, private namespaces, outer process access and Git protection")


if __name__ == "__main__":
    main()
