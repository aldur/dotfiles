"""Complete real Codex and Claude turns against local TLS API fixtures.

The outer namespace has its own network, home, credentials and CA. Only its
loopback server is reachable. The inner namespace is the production sandbox.
Pass a standalone binary to the Nix runner to test self-managed updates too.
"""

import argparse
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from itertools import product
import json
import os
from pathlib import Path
from queue import Empty, Queue
import ssl
import subprocess
import sys
import tempfile
from threading import Thread
import time
from urllib.parse import urlsplit

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


ANSWER = "sandbox transport completed"
PROMPT = "Return the transport fixture response."


def run(command, timeout=30, **kwargs):
    try:
        return subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"").decode(errors="replace")
        errors = (error.stderr or b"").decode(errors="replace")
        raise AssertionError(
            f"Command timed out: {command}\nstdout:\n{output}\nstderr:\n{errors}"
        ) from None


def certificate(directory, name, issuer=None, stem=None):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    now = datetime.now(timezone.utc)
    builder = (x509.CertificateBuilder().subject_name(subject)
               .issuer_name(issuer[0].subject if issuer else subject)
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(now - timedelta(days=1))
               .not_valid_after(now + timedelta(days=2))
               .add_extension(x509.BasicConstraints(ca=issuer is None, path_length=None), critical=True))
    if issuer:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(name)]), critical=False)
    cert = builder.sign(issuer[1] if issuer else key, hashes.SHA256())
    (directory / f"{stem or name}.pem").write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (directory / f"{stem or name}.key").write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    return cert, key


class Responses(BaseHTTPRequestHandler):
    def handle(self):
        try:
            super().handle()
        except ssl.SSLError as error:
            self.server.tls_errors.put(error.reason)
        except ConnectionError:
            # Native clients can close speculative or idle connections.
            pass

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        request = json.loads(body)
        path = urlsplit(self.path).path
        self.server.requests.append((path, request))
        if path == "/v1/messages/count_tokens":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"input_tokens":1}')
            return
        if path not in ("/v1/responses", "/v1/messages") or not request.get("stream"):
            self.send_error(400, "expected a streaming model request")
            return
        events = self.codex_events() if path == "/v1/responses" else self.claude_events(request)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for event in events:
            self.wfile.write(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n".encode())
            self.wfile.flush()

    def codex_events(self):
        item = {"id": "msg_fixture", "type": "message", "role": "assistant",
                "status": "completed", "content": [
                    {"type": "output_text", "text": ANSWER, "annotations": []}]}
        return [
            {"type": "response.created", "response": {"id": "resp_fixture", "status": "in_progress"}},
            {"type": "response.output_item.added", "output_index": 0,
             "item": dict(item, status="in_progress", content=[])},
            {"type": "response.output_text.delta", "item_id": item["id"],
             "output_index": 0, "content_index": 0, "delta": ANSWER},
            {"type": "response.output_item.done", "output_index": 0, "item": item},
            {"type": "response.completed", "response": {
                "id": "resp_fixture", "status": "completed", "output": [item],
                "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}},
        ]

    def claude_events(self, request):
        return [
            {"type": "message_start", "message": {
                "id": "msg_fixture", "type": "message", "role": "assistant",
                "model": request["model"], "content": [], "stop_reason": None,
                "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 0}}},
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": ANSWER}},
            {"type": "content_block_stop", "index": 0},
            {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
             "usage": {"output_tokens": 1}},
            {"type": "message_stop"},
        ]


class TLSServer(ThreadingHTTPServer):
    def get_request(self):
        connection, address = self.socket.accept()
        connection.settimeout(5)
        try:
            return self.context.wrap_socket(connection, server_side=True), address
        except ssl.SSLError as error:
            self.tls_errors.put(error.reason)
            connection.close()
            raise


@contextmanager
def server():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("/fixture/fixture.test.pem", "/fixture/fixture.test.key")
    httpd = TLSServer(("127.0.0.1", 0), Responses)
    httpd.context = context
    httpd.tls_errors = Queue()
    httpd.requests = []
    thread = Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield httpd
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


def configure(kind, port, hostname="fixture.test"):
    if kind == "claude":
        (Path.home() / ".claude/settings.json").write_text(json.dumps({
            "disableAllHooks": True,
            "env": {
                "ANTHROPIC_BASE_URL": f"https://{hostname}:{port}",
                "ANTHROPIC_API_KEY": "sk-fixture-no-network",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                "DISABLE_AUTOUPDATER": "1",
            },
        }))
    else:
        config = Path.home() / ".codex/config.toml"
        config.write_text(f'''model = "gpt-5"
model_provider = "fixture"
check_for_update_on_startup = false
[analytics]
enabled = false
[feedback]
enabled = false
[model_providers.fixture]
name = "Local transport fixture"
base_url = "https://{hostname}:{port}/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
stream_idle_timeout_ms = 5000
''')


def inside(args):
    manifest = json.loads(Path(args.manifest).read_text())
    kind = args.agent
    launcher = manifest["cases"][3]["launchers"][kind]
    native = str(Path.home() / ".local/bin" / kind)
    version = run([native, "--version"])
    assert version.returncode == 0, version.stderr
    print(f"testing {args.layout}: {version.stdout.strip()}", flush=True)
    # Exercise the regular cached startup path of the production Claude wrapper.
    (Path.home() / ".claude/yolo-refresh").write_text(f"{version.stdout.split()[0]} {int(time.time())}\n")
    command = (["exec", "--skip-git-repo-check", "--json", "--color", "never", PROMPT]
               if kind == "codex" else
               ["-p", "--model", "sonnet", "--output-format", "json", "--max-turns", "1",
                "--tools", "", "--strict-mcp-config", PROMPT])
    with server() as httpd:
        port = httpd.server_port
        configure(kind, port)
        for label, prefix in [("host control", [native]), ("sandbox", [launcher])]:
            print(f"running {kind} {args.layout}: {label}", flush=True)
            before = len(httpd.requests)
            result = run(prefix + command)
            assert result.returncode == 0, f"{kind} {args.layout}: {label}\n{result.stdout}\n{result.stderr}"
            if kind == "codex":
                events = [json.loads(line) for line in result.stdout.splitlines()]
                assert any(event.get("type") == "turn.completed" for event in events), events
                assert any(event.get("item", {}).get("text") == ANSWER for event in events), events
            else:
                response = json.loads(result.stdout)
                assert response["type"] == "result" and not response["is_error"], response
                assert response["result"] == ANSWER, response
            expected_path = "/v1/responses" if kind == "codex" else "/v1/messages"
            requests = [(path, body) for path, body in httpd.requests[before:]
                        if path == expected_path and PROMPT in json.dumps(body)]
            assert len(requests) == 1, httpd.requests[before:]
            print(f"passed {kind} {args.layout}: {label} completed a TLS model turn", flush=True)

        # The same real client must reject an unrelated root and a wrong hostname.
        # Check that no application request reached the server in either case.
        for label, hostname, identity in [
            ("untrusted CA", "fixture.test", "untrusted-server"),
            ("wrong hostname", "wrong.test", "fixture.test"),
        ]:
            configure(kind, port, hostname)
            httpd.context.load_cert_chain(f"/fixture/{identity}.pem", f"/fixture/{identity}.key")
            before = len(httpd.requests)
            # Codex may keep waiting for connectivity even with retries set to
            # zero. Observe its certificate-rejection alert at the TLS server,
            # then stop it; a timeout or an unrelated startup error cannot pass.
            assert httpd.tls_errors.empty()
            if kind == "claude":
                # Bun closes the socket without a TLS alert, but Claude emits
                # a structured terminal certificate error. Require that exact
                # class of failure as well as no HTTP request reaching us.
                result = run([launcher, *command])
                response = json.loads(result.stdout)
                assert result.returncode != 0 and response["is_error"], (result.returncode, response)
                expected = ("certificate verification failed" if label == "untrusted CA"
                            else "certificate hostname mismatch")
                assert expected in response["result"].lower(), response
            else:
                proc = subprocess.Popen([launcher, *command],
                                        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                reason = None
                try:
                    reason = httpd.tls_errors.get(timeout=15)
                except Empty:
                    pass
                finally:
                    proc.terminate()
                    try:
                        output, errors = proc.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        output, errors = proc.communicate(timeout=5)
                assert reason in ("TLSV1_ALERT_UNKNOWN_CA", "SSLV3_ALERT_BAD_CERTIFICATE",
                                  "SSLV3_ALERT_CERTIFICATE_UNKNOWN"), (label, reason, output, errors)
                assert ANSWER.encode() not in output, (label, output, errors)
            assert len(httpd.requests) == before, (label, httpd.requests)
            print(f"passed {kind} {args.layout}: {label} rejected before HTTP", flush=True)


def outside(args):
    manifest = json.loads(Path(args.manifest).read_text())
    with tempfile.TemporaryDirectory(prefix="agent-transport-") as temporary:
        fixture = Path(temporary)
        root = certificate(fixture, "trusted")
        certificate(fixture, "fixture.test", root)
        untrusted = certificate(fixture, "untrusted")
        certificate(fixture, "fixture.test", untrusted, stem="untrusted-server")
        (fixture / "passwd").write_text(f"tester:x:{os.getuid()}:{os.getgid()}::/home/tester:/bin/sh\n")
        (fixture / "hosts").write_text("127.0.0.1 localhost fixture.test wrong.test\n")
        (fixture / "nsswitch.conf").write_text("hosts: files\n")
        kinds = (args.agent,) if args.agent else ("codex", "claude")
        for kind, layout in product(kinds, ("plain", "nixos")):
            home = fixture / kind / layout
            for name in ("Work", ".codex", ".claude", ".local/bin"):
                (home / name).mkdir(parents=True)
            (home / ".claude.json").write_text('{"hasCompletedOnboarding":true}')
            binary = getattr(args, kind) or manifest["native"][kind]
            # No real agent state or credentials enter this namespace.
            command = [manifest["bwrap"], "--unshare-user", "--unshare-pid", "--unshare-net",
                       "--die-with-parent", "--tmpfs", "/", "--ro-bind", "/nix/store", "/nix/store",
                       "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
                       "--bind", str(home), "/home/tester", "--ro-bind", str(fixture), "/fixture",
                       "--ro-bind", str(Path(binary).resolve()), f"/home/tester/.local/bin/{kind}",
                       "--ro-bind", str(fixture / "passwd"), "/etc/passwd",
                       "--ro-bind", str(fixture / "hosts"), "/etc/hosts",
                       "--ro-bind", str(fixture / "nsswitch.conf"), "/etc/nsswitch.conf",
                       "--clearenv", "--setenv", "HOME", "/home/tester",
                       "--setenv", "PATH", f"/home/tester/.local/bin:{manifest['path']}",
                       "--setenv", "XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}",
                       "--dir", f"/run/user/{os.getuid()}",
                       "--setenv", "SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt",
                       "--chdir", "/home/tester/Work"]
            for name in ("/run/current-system/sw", "/lib", "/lib64"):
                if Path(name).exists():
                    command += ["--ro-bind", name, name]
            for name in ("NIX_LD", "NIX_LD_LIBRARY_PATH"):
                if name in os.environ:
                    command += ["--setenv", name, os.environ[name]]
            for name, source in [("ca-certificates.crt", "trusted.pem"), ("ca-bundle.crt", "trusted.pem")]:
                target = f"/etc/ssl/certs/{name}"
                if layout == "nixos":
                    command += ["--symlink", f"/etc/static/ssl/certs/{name}", target]
                    target = f"/etc/static/ssl/certs/{name}"
                command += ["--ro-bind", str(fixture / source), target]
            command += ["--", manifest["dbus"], f"--config-file={manifest['dbusConfig']}", "--",
                        sys.executable, str(Path(__file__).resolve()), "--inside",
                        "--layout", layout, "--agent", kind, "--manifest", args.manifest]
            result = run(command, timeout=150)
            assert result.returncode == 0, f"{kind} {layout}\n{result.stdout}\n{result.stderr}"
            print(result.stdout, end="", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    for option in ("codex", "claude", "layout"):
        parser.add_argument("--" + option)
    parser.add_argument("--agent", choices=("codex", "claude"))
    parser.add_argument("--inside", action="store_true")
    arguments = parser.parse_args()
    (inside if arguments.inside else outside)(arguments)
