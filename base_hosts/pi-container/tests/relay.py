"""Exercise concurrent Pi relays in separate network namespaces."""

from http.server import BaseHTTPRequestHandler
import os
from pathlib import Path
import select
import socket
from socketserver import ThreadingUnixStreamServer
import subprocess
import sys
import tempfile
from threading import Thread
from urllib.request import urlopen


class Model(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"fixture" * 600_000
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def client():
    assert urlopen(os.environ["LLAMA_BASE_URL"] + "/models", timeout=5).read() == b"fixture" * 600_000
    print("ready", flush=True)
    assert sys.stdin.readline() == "fixture input\n"
    raise SystemExit(23)


def main():
    wrapper, relay = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="pi-relay-test-") as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir()
        work = root / "work"
        work.mkdir()
        endpoint = root / "model.sock"
        server = ThreadingUnixStreamServer(str(endpoint), Model)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        occupied = socket.socket()
        occupied.bind(("127.0.0.1", 8080))
        occupied.listen()
        env = dict(os.environ, HOME=str(home), LLAMA_SOCKET_PATH=str(endpoint))
        processes = []
        try:
            for _ in range(2):
                processes.append(subprocess.Popen([
                    wrapper, "--profile", "pi", "--workspace", str(work), "--ro", str(endpoint),
                    "--", relay, sys.executable, __file__, "client",
                ], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            for process in processes:
                assert select.select([process.stdout], [], [], 15)[0], "relay did not start"
                line = process.stdout.readline()
                assert line == "ready\n", (line, process.communicate(timeout=5))
            for process in processes:
                stdout, stderr = process.communicate("fixture input\n", timeout=10)
                assert process.returncode == 23, (process.returncode, stdout, stderr)
            occupied.close()
            # The relay also serves explicit commands outside the sandbox.
            result = subprocess.run([relay, sys.executable, __file__, "client"], env=env,
                                    input="fixture input\n", capture_output=True, text=True, timeout=15)
            assert result.returncode == 23, (result.stdout, result.stderr)
            with socket.socket() as probe:
                assert probe.connect_ex(("127.0.0.1", 8080)) != 0, "relay did not stop"
            missing = dict(env, LLAMA_SOCKET_PATH=str(root / "missing.sock"))
            result = subprocess.run([relay, sys.executable, "-c", "raise SystemExit(90)"], env=missing,
                                    capture_output=True, text=True, timeout=5)
            assert result.returncode == 1 and "inference socket missing" in result.stderr, result
            print("passed: private relays, large responses, stdin, exit status and cleanup")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait()
            occupied.close()
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    if sys.argv[1:2] == ["client"]:
        client()
    else:
        main()
