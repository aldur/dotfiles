import contextlib
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time

wrapper_a, wrapper_b, plugin_a, plugin_b = sys.argv[1:]


class Pi:
    def __init__(self, wrapper, root, extra=()):
        self.errors = tempfile.TemporaryFile(mode="w+")
        self.process = subprocess.Popen(
            [wrapper, "--offline", "--mode", "rpc", "--no-session", *extra],
            cwd=root,
            env=os.environ | {
                "PI_CODING_AGENT_DIR": str(root / "agent"),
                "PI_TEST_LOG": str(root / "loaded.jsonl"),
            },
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors,
        )
        self.pending = b""

    def request(self, command, **fields):
        request = {"id": command, "type": command, **fields}
        self.process.stdin.write((json.dumps(request) + "\n").encode())
        self.process.stdin.flush()
        deadline = time.monotonic() + 30
        while True:
            if b"\n" not in self.pending:
                remaining = deadline - time.monotonic()
                assert remaining > 0 and select.select([self.process.stdout], [], [], remaining)[0], "RPC timeout"
                chunk = os.read(self.process.stdout.fileno(), 65536)
                assert chunk, "Pi exited before its response"
                self.pending += chunk
                continue
            line, self.pending = self.pending.split(b"\n", 1)
            event = json.loads(line)
            if event.get("type") == "response" and event.get("id") == command:
                assert event["success"], event
                return event.get("data")

    def start(self, root, build, user=True):
        self.request("get_state")
        receipt = json.loads((root / "loaded.jsonl").read_text().splitlines()[-1])
        assert receipt == {"build": build, "child": False, "user": user}, receipt

    def child(self, root, build, user=True):
        result_path = root / "child-result.json"
        result_path.unlink(missing_ok=True)
        self.request("prompt", message=f"/check-child {result_path}")
        deadline = time.monotonic() + 30
        while not result_path.exists():
            assert time.monotonic() < deadline, "Child timeout"
            time.sleep(0.05)
        result = json.loads(result_path.read_text())
        assert result["details"]["results"][0]["exitCode"] == 0, result
        receipt = json.loads((root / "loaded.jsonl").read_text().splitlines()[-1])
        assert receipt == {"build": build, "child": True, "user": user}, receipt

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.errors.seek(0)
        errors = self.errors.read()
        self.errors.close()
        assert "Failed to load extension" not in errors and "conflicts with" not in errors, errors


with tempfile.TemporaryDirectory(prefix="pi-extensions-") as temporary:
    root = Path(temporary)
    agent = root / "agent"
    (agent / "agents").mkdir(parents=True)
    (agent / "agents/probe.md").write_text("---\nname: probe\ndescription: Test agent\n---\n")
    settings = agent / "settings.json"
    user = agent / "user.ts"
    user.write_text('''export default function(pi) {
      globalThis.piTestUserLoaded = true;
      pi.registerCommand("user-extension", { description: "User extension", handler: async () => {} });
    }''')

    # A clean home must load the bundled plugins in both processes.
    with contextlib.closing(Pi(wrapper_a, root)) as pi:
        pi.start(root, "A", user=False)
        pi.child(root, "A", user=False)

    settings.write_text(json.dumps({"extensions": [str(user)], "theme": "dark"}))
    for wrapper, build in [(wrapper_a, "A"), (wrapper_b, "B")]:
        with contextlib.closing(Pi(wrapper, root)) as pi:
            pi.start(root, build)
            commands = pi.request("get_commands")["commands"]
            assert any(command["name"] == "user-extension" for command in commands), commands
            assert any(command["name"] == "system-prompt" for command in commands), commands
            sources = {command["name"]: command["sourceInfo"]["path"]
                       for command in commands if command["source"] == "extension"}
            assert sources["check-child"] == (plugin_a if build == "A" else plugin_b), sources
            assert sources["user-extension"] == str(user), sources
            assert sources["system-prompt"].endswith("-pi-system-prompt/index.ts"), sources
            assert len({sources[name] for name in ["check-child", "user-extension", "system-prompt"]}) == 3
            pi.child(root, build)

    # A later wrapper must not change the plugins in an earlier wrapper's children.
    with contextlib.closing(Pi(wrapper_a, root)) as first:
        first.start(root, "A")
        with contextlib.closing(Pi(wrapper_b, root)) as second:
            second.start(root, "B")
            first.child(root, "A")
            second.child(root, "B")

    with contextlib.closing(Pi(wrapper_b, root, ["--no-extensions"])) as pi:
        pi.start(root, "B", user=False)
        commands = pi.request("get_commands")["commands"]
        assert not any(command["name"] == "user-extension" for command in commands), commands
        pi.child(root, "B")

print("Pi revisions, clean home, individual extensions, and children passed")
