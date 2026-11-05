"""Check Faraday with local endpoints and explicit failure conditions."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import select
import signal
import socket
import subprocess
import sys
import tempfile
from threading import Thread
import time
from urllib.request import urlopen


FARADAY = os.environ.get("FARADAY", "faraday")


def run(*args, status=0, error=None):
    result = subprocess.run([FARADAY, *map(str, args)], capture_output=True,
                            text=True, timeout=10)
    assert result.returncode == status, (args, result)
    if error is not None:
        assert error in result.stderr, result
    return result.stdout


def python(code, *args, options=()):
    return run(*options, "--", sys.executable, "-c", code, *args)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"fixture response")

    def log_message(self, *_):
        pass


def no_process(pattern):
    result = subprocess.run(["pgrep", "-f", "--", pattern], capture_output=True,
                            text=True, timeout=5)
    assert result.returncode in (0, 1), result
    return result.returncode == 1


def wait_until(predicate):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("condition did not become true within five seconds")


assert os.geteuid() != 0, "run as a non-root user"
with tempfile.TemporaryDirectory(prefix="faraday-test-") as directory, \
        ThreadingHTTPServer(("127.0.0.1", 0), Handler) as allowed, \
        ThreadingHTTPServer(("127.0.0.1", 0), Handler) as blocked:
    root = Path(directory)
    os.environ["TMPDIR"] = str(root)
    os.environ["HOME"] = str(root / "home")
    Path.home().mkdir()
    for server in (allowed, blocked):
        Thread(target=server.serve_forever, daemon=True).start()
        with urlopen(f"http://127.0.0.1:{server.server_port}", timeout=5) as response:
            assert response.read() == b"fixture response"
    allow = ("--allow", f"127.0.0.1:{allowed.server_port}")
    body = python("from urllib.request import urlopen; import sys; "
                  "print(urlopen(sys.argv[1], timeout=3).read().decode())",
                  f"http://127.0.0.1:{allowed.server_port}", options=allow)
    assert body == "fixture response\n", body
    denied = """
import errno, socket, sys
try:
    socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=3)
except OSError as error:
    assert error.errno == errno.ECONNREFUSED, error
else:
    raise AssertionError('unlisted endpoint was reachable')
"""
    python(denied, blocked.server_port, options=allow)
    python(denied, allowed.server_port)
    interfaces = run("--", "cat", "/proc/net/dev")
    assert [line.split(":")[0].strip() for line in interfaces.splitlines()[2:]] == ["lo"]
    print("passed: allowed and blocked local endpoints", flush=True)

    probe = Path.home() / "probe"
    probe.write_text("host control")
    python("""
import errno, sys
try:
    open(sys.argv[1], 'w')
except OSError as error:
    assert error.errno == errno.EROFS, error
else:
    raise AssertionError('home was writable')
""", probe)
    write = "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('written')"
    for options in (("--rw", str(Path.home())), ("--writable-home",)):
        python(write, probe, options=options)
        assert probe.read_text() == "written"
        probe.unlink()
    scratch = f"/tmp/{root.name}-scratch"
    python(write, scratch)
    assert not Path(scratch).exists()
    mask = root / "masked"
    mask.mkdir()
    (mask / "secret").touch()
    for options in (("--mask", str(mask)), ("--rw", str(mask), "--mask", str(mask))):
        python("from pathlib import Path; import sys; assert list(Path(sys.argv[1]).iterdir()) == []",
               mask, options=options)
    run("--mask", root / "missing", "--", "true")
    print("passed: writable paths and masks", flush=True)

    mapped = run(*allow, "--map", "faraday-test.internal", "--", "getent", "hosts", "faraday-test.internal")
    assert mapped.split()[0] == "127.0.0.1", mapped
    # Supply a host-side socket even when the builder does not run nscd.
    nscd = root / "nscd"
    nscd.mkdir()
    with socket.socket(socket.AF_UNIX) as host_socket:
        host_socket.bind(str(nscd / "socket"))
        result = subprocess.run([
            "bwrap", "--tmpfs", "/", "--ro-bind", "/nix", "/nix", "--ro-bind", "/etc", "/etc",
            "--proc", "/proc", "--dev", "/dev", "--bind", str(root), str(root), "--chdir", str(root),
            "--dir", "/tmp", "--dir", "/run", "--ro-bind", str(nscd), "/run/nscd",
            "--", "bash", "-c",
            'test -S /run/nscd/socket && exec "$@"', "fixture", FARADAY, "--", sys.executable,
            "-c", "from pathlib import Path; assert list(Path('/run/nscd').iterdir()) == []",
        ], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result
    print("passed: name mapping and nscd socket masking", flush=True)

    for options, status in (((), 42), (allow, 7)):
        run(*options, "--", "bash", "-c", f"exit {status}", status=status)
    for args, error in (
        (("--allow", "nonsense", "--", "true"), "malformed --allow"),
        (("--allow", "127.0.0.1:99999", "--", "true"), "bad port"),
        (allow, "missing command"),
        ((*allow, *allow, "--", "true"), "assigned twice"),
    ):
        run(*args, status=1, error=error)
    # A bound socket without listen() reserves a port that rejects connections.
    with socket.socket() as unavailable:
        unavailable.bind(("127.0.0.1", 0))
        run("--allow", f"127.0.0.1:{unavailable.getsockname()[1]}", "--", "true",
            status=1, error="cannot reach")
    print("passed: validation and exit status", flush=True)

    relay_pattern = r"UNIX-(LISTEN|CONNECT):" + re.escape(str(root)) + r"/faraday\."

    def cleaned_up():
        return no_process(relay_pattern) and not list(root.glob("faraday.*"))

    run(*allow, "--", "true")
    wait_until(cleaned_up)
    for sig in (signal.SIGINT, signal.SIGTERM):
        marker = f"{root.name}-child-{sig.name}"
        child = """
import signal, sys, time
# Shell background jobs can inherit SIGINT as ignored.
signal.signal(signal.SIGINT, lambda *_: sys.exit(130))
print('ready', flush=True)
while True:
    time.sleep(60)
"""
        process = subprocess.Popen([FARADAY, *allow, "--", sys.executable, "-c", child, marker],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)
        try:
            assert select.select([process.stdout], [], [], 5)[0], "child did not start"
            assert os.read(process.stdout.fileno(), 1024) == b"ready\n", "child exited before readiness"
            assert process.poll() is None
            assert not no_process(re.escape(marker) + "$"), "child process was not observed"
            if sig == signal.SIGINT:
                os.killpg(process.pid, sig)
            else:
                process.send_signal(sig)
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == 128 + sig, (process.returncode, stdout, stderr)
            wait_until(lambda: cleaned_up() and no_process(re.escape(marker) + "$"))
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        print(f"passed: {sig.name} stops the child and removes relays", flush=True)
