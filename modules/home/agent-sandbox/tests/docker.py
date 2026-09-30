"""Check Docker socket access using local fixtures, without a Docker daemon."""

from contextlib import contextmanager
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
from threading import Event, Thread


wrapper = sys.argv[1]
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
base_env = {name: value for name, value in os.environ.items()
            if name not in ("DOCKER_HOST", "DOCKER_CONTEXT")}


@contextmanager
def service(path, reply, rootless=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path))
    server.listen()
    server.settimeout(0.1)
    stopped = Event()

    def serve():
        while not stopped.is_set():
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            with client:
                client.settimeout(3)
                request = client.recv(4096)
                if request.startswith(b"GET /info "):
                    body = json.dumps({"SecurityOptions": ["name=rootless"] if rootless else []}).encode()
                    client.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
                                   + b"\r\nConnection: close\r\n\r\n" + body)
                else:
                    client.sendall(reply.encode())

    thread = Thread(target=serve)
    thread.start()
    try:
        yield
    finally:
        stopped.set()
        thread.join(timeout=2)
        server.close()
        path.unlink()
        assert not thread.is_alive()


def launch(options, code, *args, env=None, error=None):
    result = subprocess.run(
        [wrapper, *options, "--", sys.executable, "-c", code, *args],
        env=base_env | (env or {}), capture_output=True, text=True, timeout=15,
    )
    if error is None:
        assert result.returncode == 0, (options, result.stderr)
    else:
        assert result.returncode != 0 and error in result.stderr, result
    assert not list(Path("/tmp").glob("agent-sandbox-dbus-proxy.*"))


client = """
import os, socket, sys
from pathlib import Path
host = os.environ['DOCKER_HOST']
assert host == f'unix:///run/user/{os.getuid()}/docker.sock', host
assert 'DOCKER_CONTEXT' not in os.environ
assert not (Path.home() / '.docker/config.json').exists()
assert not Path('/run/other-service/socket').exists()
with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(3)
    connection.connect(host.removeprefix('unix://'))
    connection.sendall(b'probe')
    assert connection.recv(64).decode() == sys.argv[1]
"""

credentials = Path.home() / ".docker/config.json"
credentials.parent.mkdir(exist_ok=True)
credentials.write_text('{"auths":{"fixture.invalid":{"auth":"fixture"}}}')
rootless = runtime / "docker.sock"
system = Path("/var/run/docker.sock")
custom = Path("/tmp/custom docker/socket")
alternate_runtime = Path("/tmp/docker-runtime")
with service(system, "system", rootless=False):
    with service(rootless, "rootless"), service(custom, "custom"):
        launch([], """
import os
from pathlib import Path
assert 'DOCKER_HOST' not in os.environ
assert not (Path(os.environ['XDG_RUNTIME_DIR']) / 'docker.sock').exists()
assert not Path('/var/run/docker.sock').exists()
""", env={"DOCKER_HOST": f"unix://{rootless}"})
        launch(["--docker"], client, "rootless")
        launch(["--profile", "docker"], client, "rootless")
        launch(["--docker", "--env", "DOCKER_HOST"], client, "custom",
               env={"DOCKER_HOST": f"unix://{custom}"})
        launch(["--docker"], "", env={"DOCKER_HOST": f"unix://{system}"},
               error="rootful Docker is not allowed")
        with service(alternate_runtime / "docker.sock", "alternate"):
            launch(["--docker"], client, "alternate",
                   env={"XDG_RUNTIME_DIR": str(alternate_runtime)})
        for host in ("tcp://localhost:2375", "ssh://fixture", "unix://relative"):
            launch(["--docker"], "", env={"DOCKER_HOST": host},
                   error="requires a local Unix socket")
        launch(["--docker"], "", env={"DOCKER_CONTEXT": "fixture"},
               error="Docker contexts are not supported")
        launch(["--docker"], "", env={"DOCKER_HOST": "unix:///missing/docker.sock"},
               error="Docker socket not found")
        custom.chmod(0o400)
        try:
            launch(["--docker"], "", env={"DOCKER_HOST": f"unix://{custom}"},
                   error="Docker socket is not writable")
        finally:
            custom.chmod(0o600)
    # Never use the system socket when the user's rootless socket is absent.
    launch(["--docker"], "", error="Docker socket not found")
with service(rootless, "rootful", rootless=False):
    launch(["--docker"], "", error="rootful Docker is not allowed")
launch(["--docker"], "", error="Docker socket not found")
rootless.touch()
try:
    launch(["--docker"], "", error="Docker socket not found")
finally:
    rootless.unlink()
    credentials.unlink()
print("passed: rootless Docker is opt-in; custom sockets work; rootful, missing and invalid sockets fail", flush=True)
