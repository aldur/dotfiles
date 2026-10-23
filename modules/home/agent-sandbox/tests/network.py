"""Exercise private networking against local fixtures in a disposable VM."""

import http.client
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import runpy
import signal
import socket
from socketserver import UnixStreamServer
import subprocess
import sys
from threading import Thread
import time
from urllib.request import urlopen


def wait_for(predicate):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("condition did not become true")


def check_resolver(path):
    resolver = runpy.run_path(path)["resolver"]
    text, args = resolver(
        "search fixture.test\n"
        "nameserver 127.0.0.53\n"
        "nameserver ::1\n"
        "nameserver 192.0.2.2\n"
        "nameserver 2001:db8::2\n"
        "nameserver 192.0.2.3\n"
        "options timeout:1 attempts:2\n"
    )
    assert text == (
        "search fixture.test\n"
        "nameserver 169.254.1.53\n"
        "nameserver fd00::53\n"
        "nameserver 192.0.2.2\n"
        "nameserver 2001:db8::2\n"
        "nameserver 192.0.2.3\n"
        "options timeout:1 attempts:2\n"
    ), text
    assert args == [
        "--dns-forward", "169.254.1.53", "--dns-host", "127.0.0.53",
        "--dns-forward", "fd00::53", "--dns-host", "::1",
    ], args


def inside():
    print("network fixture: DNS", file=sys.stderr, flush=True)
    assert socket.gethostbyname("fixture.test") == "192.0.2.2"
    print("network fixture: outbound HTTP", file=sys.stderr, flush=True)
    assert urlopen("http://fixture.test:18080/answer", timeout=5).read() == b"peer"
    try:
        socket.create_connection(("127.0.0.1", 18080), timeout=1)
    except OSError:
        pass
    else:
        raise AssertionError("host loopback is reachable")
    # Both namespaces can bind the host's occupied port. No inbound port is
    # forwarded, including ports opened after pasta starts.
    listeners = []
    for port in (18080, 18081):
        listener = socket.socket()
        listener.bind(("0.0.0.0", port))
        listener.listen()
        listeners.append(listener)
    connection = http.client.HTTPConnection("localhost")
    connection.sock = socket.socket(socket.AF_UNIX)
    connection.sock.connect(os.environ["XDG_RUNTIME_DIR"] + "/activity.sock")
    connection.request("POST", "/activity", b'{"event":"working"}')
    assert connection.getresponse().status == 204
    connection.close()
    connection = http.client.HTTPConnection("localhost")
    connection.sock = socket.socket(socket.AF_UNIX)
    connection.sock.connect(os.environ["DOCKER_HOST"].removeprefix("unix://"))
    connection.request("GET", "/info")
    assert "name=rootless" in json.loads(connection.getresponse().read())["SecurityOptions"]
    connection.close()
    Path("ready").write_text(os.readlink("/proc/self/ns/net"))
    if "hang" in sys.argv:
        subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"], start_new_session=True)
        while True:
            time.sleep(1)
    wait_for(lambda: Path("finish").exists())
    raise SystemExit(23)


class Activity(BaseHTTPRequestHandler):
    events = []

    def do_POST(self):
        self.events.append(self.rfile.read(int(self.headers["Content-Length"])))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_):
        pass


class Docker(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'{"SecurityOptions":["name=rootless"]}'
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def descendants(pid):
    result = set()
    try:
        children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
    except FileNotFoundError:
        return result
    for child in map(int, children):
        result.add(child)
        result.update(descendants(child))
    return result


def main():
    wrapper = sys.argv[1]
    check_resolver(sys.argv[2])
    def command(*args):
        subprocess.run(args, check=True)

    # The peer is a separate network. No public endpoint or real credential
    # is used. The host DNS stub must work from inside the sandbox too.
    for args in (
        ("netns", "add", "peer"),
        ("link", "add", "uplink", "type", "veth", "peer", "name", "peer0"),
        ("link", "set", "peer0", "netns", "peer"),
        ("address", "add", "192.0.2.1/24", "dev", "uplink"),
        ("link", "set", "uplink", "up"),
        ("-n", "peer", "address", "add", "192.0.2.2/24", "dev", "peer0"),
        ("-n", "peer", "link", "set", "peer0", "up"),
        ("-n", "peer", "link", "set", "lo", "up"),
        ("route", "replace", "default", "via", "192.0.2.2", "dev", "uplink"),
    ):
        command("ip", *args)
    Path("/etc/resolv.conf").write_text("nameserver 127.0.0.53\noptions timeout:1 attempts:2\n")
    fixture = Path("/srv/fixture")
    fixture.mkdir()
    (fixture / "answer").write_text("peer")
    processes = [
        subprocess.Popen(["ip", "netns", "exec", "peer", sys.executable, "-m", "http.server",
                          "18080", "--bind", "192.0.2.2", "--directory", str(fixture)]),
        subprocess.Popen(["dnsmasq", "--no-daemon", "--no-resolv", "--bind-interfaces",
                          "--listen-address=127.0.0.53", "--address=/fixture.test/192.0.2.2"]),
        subprocess.Popen(["ip", "netns", "exec", "peer", "dnsmasq", "--no-daemon",
                          "--no-resolv", "--bind-interfaces", "--listen-address=192.0.2.2",
                          "--address=/fixture.test/192.0.2.2"]),
    ]
    host = ThreadingHTTPServer(("127.0.0.1", 18080), BaseHTTPRequestHandler)
    Thread(target=host.serve_forever, daemon=True).start()
    runtime = Path("/run/user/1000")
    runtime.mkdir(parents=True, exist_ok=True)
    os.chown(runtime, 1000, 100)
    activity = UnixStreamServer(str(runtime / "activity.sock"), Activity)
    os.chown(runtime / "activity.sock", 1000, 100)
    Thread(target=activity.serve_forever, daemon=True).start()
    env = dict(HOME="/home/tester", PATH=os.environ["PATH"], XDG_RUNTIME_DIR=str(runtime))

    def user():
        os.setgroups([])
        os.setgid(100)
        os.setuid(1000)

    def launch(work, *args):
        process = subprocess.Popen([wrapper, "--docker", "--profile", "hooks", "--workspace", str(work),
                                    "--", sys.executable, __file__, "inside", *args],
                                   env=env, preexec_fn=user, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        processes.append(process)
        return process

    try:
        processes.append(subprocess.Popen([sys.executable, __file__, "docker"], env=env, preexec_fn=user))
        wait_for(lambda: (runtime / "docker.sock").exists())
        def peer_ready():
            try:
                return (socket.gethostbyname("fixture.test") == "192.0.2.2"
                        and urlopen("http://192.0.2.2:18080/answer", timeout=1).read() == b"peer")
            except OSError:
                return False
        wait_for(peer_ready)
        for number, stop in enumerate((None, signal.SIGTERM, signal.SIGKILL)):
            if number == 1:
                # The first server has no listener. The peer is the backup.
                Path("/etc/resolv.conf").write_text(
                    "nameserver 127.0.0.54\nnameserver 192.0.2.2\n"
                    "options timeout:1 attempts:2\n"
                )
                wait_for(peer_ready)
            work = Path(f"/home/tester/work-{number}")
            work.mkdir()
            os.chown(work, 1000, 100)
            process = launch(work, *(["hang"] if stop else []))
            def ready():
                if process.poll() is not None:
                    raise AssertionError(process.communicate())
                return (work / "ready").exists()
            try:
                wait_for(ready)
            except AssertionError:
                process.terminate()
                raise AssertionError(process.communicate(timeout=30))
            assert (work / "ready").read_text() != os.readlink("/proc/self/ns/net")
            try:
                socket.create_connection(("127.0.0.1", 18081), timeout=1)
            except OSError:
                pass
            else:
                raise AssertionError("sandbox port was forwarded")
            pids = descendants(process.pid)
            assert pids
            if stop:
                process.send_signal(stop)
            else:
                (work / "finish").touch()
            stdout, stderr = process.communicate(timeout=30)
            if not stop:
                assert process.returncode == 23, (process.returncode, stdout, stderr)
            wait_for(lambda: all(not Path(f"/proc/{pid}").exists() for pid in pids))
            assert not list(Path("/tmp").glob("agent-sandbox-network-*"))
        assert len(Activity.events) == 3, Activity.events
        result = subprocess.run([wrapper, "--network", "host", "--profile", "hooks", "--workspace",
                                 str(work), "--", sys.executable, "-c",
                                 "import socket; socket.create_connection(('127.0.0.1',18080),timeout=1)"],
                                env=env, preexec_fn=user, capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr
        print("passed: DNS fallback, outbound access, port isolation, Unix activity socket, rootless Docker, exit status and cleanup")
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.kill()
            process.wait()
        host.shutdown()
        activity.shutdown()


if __name__ == "__main__":
    if sys.argv[1:2] == ["inside"]:
        inside()
    elif sys.argv[1:2] == ["docker"]:
        with UnixStreamServer(os.environ["XDG_RUNTIME_DIR"] + "/docker.sock", Docker) as server:
            server.serve_forever()
    else:
        main()
