"""Run Pi subagents with a local model fixture and real browser tools."""

import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("launcher")
parser.add_argument("directory", type=Path)
parser.add_argument("--sandbox", action="store_true")
parser.add_argument("--live", action="store_true")
parser.add_argument("--browser-package", type=Path)
parser.add_argument("--browser-key")
args = parser.parse_args()
root = args.directory.resolve()
root.mkdir(parents=True)
agent = root / "agent"
(agent / "agents").mkdir(parents=True, exist_ok=True)
if args.browser_package:
    browser_root = agent / "browser" / args.browser_key / "browser"
    browser_root.parent.mkdir(parents=True)
    browser_root.symlink_to(args.browser_package)
barrier = threading.Barrier(2)
failures = []
requests = []


def call(name, arguments):
    return {"name": name, "arguments": json.dumps(arguments)}


def script(code):
    return call("codemode", {"code": code})


def mcp(name, **arguments):
    return script(f"""
      const result = await tools.mcp__playwright_lazy__{name}({json.dumps(arguments)});
      if (result.isError) throw new Error(JSON.stringify(result));
      text(result.content.filter(item => item.type === "text"));
    """)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path.startswith("/barrier"):
            barrier.wait(timeout=60)
            body, kind = b"ready", "text/plain"
        elif self.path == "/paper.pdf":
            body, kind = b"%PDF-1.4\nfixture PDF\n%%EOF\n", "application/pdf"
        else:
            body = (b'<title>Publication</title><h1>Publication</h1><a href="/reference">Reference</a>'
                    if self.path == "/publication" else
                    b'<title>Reference</title><h1>Reference</h1><a href="/paper.pdf">Download PDF</a>')
            kind = "text/html"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        if kind == "application/pdf":
            self.send_header("Content-Disposition", 'attachment; filename="paper.pdf"')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if len(requests) > 40:
            self.send_error(500, "Too many model calls")
            return
        requests.append(request)
        messages = request["messages"]
        user = next(m["content"] for m in messages if m["role"] == "user")
        results = [m for m in messages if m["role"] == "tool"]
        worker = next((name for name in ("worker-a", "worker-b") if name in str(user)), None)
        step = len(results)
        action = None
        if worker:
            reference = ('page.locator(\'a[href="/info/rfc9112"]\').first()' if args.live else
                         'page.getByRole("link", {name:"Reference", exact:true})')
            pdf = ('page.locator(\'a[href$="rfc9112.pdf"]\').first()' if args.live else
                   'page.getByRole("link", {name:"Download PDF"})')
            actions = [
                script("""
                  const found = await searchTools("publication PDF screenshot", {namespace: "mcp__playwright_lazy"});
                  if (!found.length) throw new Error("discovery failed");
                  text(found);
                """),
                mcp("browser_navigate", url=base + "/publication"),
                mcp("browser_run_code", code=f"""async (page) => {{
                  if (await page.evaluate(() => document.cookie || localStorage.getItem('worker')))
                    throw new Error('shared state');
                  await page.evaluate(id => {{
                    document.cookie = 'worker=' + id;
                    localStorage.setItem('worker', id);
                  }}, {json.dumps(worker)});
                  await page.request.get({json.dumps(base + '/barrier?' + worker)});
                  const state = await page.evaluate(() => [document.cookie, localStorage.getItem('worker')]);
                  if (state[0] !== 'worker=' + {json.dumps(worker)} || state[1] !== {json.dumps(worker)})
                    throw new Error('context conflict');
                }}"""),
                mcp("browser_navigate", url="https://www.rfc-editor.org/info/rfc9110" if args.live else base + "/publication"),
                mcp("browser_snapshot", depth=5),
                mcp("browser_run_code", code=f"async (page) => {{ await {reference}.click(); }}"),
                mcp("browser_snapshot", depth=5),
                mcp("browser_take_screenshot", type="png"),
                mcp("browser_run_code", code=f"""async (page) => {{
                  const [download] = await Promise.all([page.waitForEvent("download"), {pdf}.click()]);
                  const error = await download.failure();
                  if (error) throw new Error(error);
                  return download.suggestedFilename();
                }}"""),
                call("bash", {"command": 'for file in .pi/browser/worker-*/*.pdf; do test -r "$file" || exit 1; head -c 5 "$file"; done'}),
            ]
            if step < len(actions):
                action = actions[step]
        elif step == 0:
            action = script('text(await describeNamespace("mcp__playwright_lazy"));')
        elif step == 1:
            if not args.browser_package and (agent / "browser").exists():
                failures.append("Tool discovery installed Chromium")
            action = call("subagent", {"tasks": [{"agent": "browser-check", "task": name} for name in ("worker-a", "worker-b")]})
        if not worker and step == 2:
            for _ in range(100):
                if not browser_processes():
                    break
                time.sleep(0.05)
            if browser_processes():
                failures.append("Browser processes survived their subagent sessions")
        if results:
            content = str(results[-1].get("content", ""))
            if any(marker in content for marker in ("Error:", "isError\":true", "isError\": true", "failed with exit code")):
                failures.append({"worker": worker, "step": step, "result": content})
                action = None
        if action:
            delta = {"role": "assistant", "tool_calls": [{"index": 0, "id": f"call_{step}", "type": "function", "function": action}]}
            reason = "tool_calls"
        else:
            delta, reason = {"role": "assistant", "content": "Browser check complete"}, "stop"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for chunk in [{"choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
                      {"choices": [{"index": 0, "delta": {}, "finish_reason": reason}]}]:
            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n")


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
base = f"http://127.0.0.1:{server.server_port}"
threading.Thread(target=server.serve_forever, daemon=True).start()
(agent / "models.json").write_text(json.dumps({"providers": {"fixture": {
    "baseUrl": base + "/v1", "api": "openai-completions", "apiKey": "fixture",
    "models": [{"id": "browser-check", "contextWindow": 128000, "maxTokens": 8192}],
}}}))
(agent / "agents/browser-check.md").write_text("---\nname: browser-check\ndescription: Browser integration test\n---\nRun the browser check.\n")
command = [str(Path(args.launcher).resolve())]
if args.sandbox:
    command += ["--network", "host", "--workspace", str(root)]
command += ["--offline", "--mode", "json", "--no-session", "--model", "fixture/browser-check", "-p", "coordinator"]
seen = {}


def browser_processes():
    alive = []
    for pid, started in seen.copy().items():
        try:
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            if fields[19] == started and fields[0] != "Z":
                alive.append(pid)
        except FileNotFoundError:
            pass
    return alive


with (root / "events.jsonl").open("w") as output, (root / "stderr.log").open("w") as errors:
    proc = subprocess.Popen(command, cwd=root, stdout=output, stderr=errors,
                            env=os.environ | {"PI_CODING_AGENT_DIR": str(agent), "PNPM_HOME": str(root / "pnpm")})
    deadline = time.monotonic() + 240
    while proc.poll() is None and time.monotonic() < deadline:
        # Track descendants by process start time to detect PID reuse.
        table = {}
        for entry in Path("/proc").glob("[0-9]*/stat"):
            try:
                fields = entry.read_text().rsplit(")", 1)[1].split()
                pid = int(entry.parent.name)
                table[pid] = (int(fields[1]), fields[19], fields[0])
            except (OSError, ValueError):
                continue
        descendants = {proc.pid}
        while True:
            added = {pid for pid, (parent, _, _) in table.items() if parent in descendants} - descendants
            if not added:
                break
            descendants.update(added)
        for pid in descendants - {proc.pid}:
            try:
                cmd = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
                if "headless" in cmd and ("--remote-debugging-pipe" in cmd or "--type=" in cmd):
                    seen[pid] = table[pid][1]
                    if "--no-sandbox" in cmd:
                        failures.append("Chromium sandbox is disabled")
                        proc.terminate()
            except FileNotFoundError:
                pass
        time.sleep(0.05)
    if proc.poll() is None:
        proc.terminate()
        proc.wait(timeout=10)
        failures.append("Pi timeout")
server.shutdown()
(root / "requests.json").write_text(json.dumps(requests, indent=2))
assert proc.returncode == 0, (proc.returncode, (root / "stderr.log").read_text())
assert not failures, failures
assert seen, "No browser process observed"
assert not browser_processes(), f"Browser processes survived Pi: {browser_processes()}"
assert len(list((agent / "browser").glob("*/browser"))) == 1, "workers did not share one browser install"
outputs = list((root / ".pi/browser").glob("worker-*"))
completed = [p for p in outputs if list(p.glob("*.png")) and list(p.glob("*.pdf"))]
assert len(completed) == 2, [(str(p), [f.name for f in p.iterdir()]) for p in outputs]
for directory in completed:
    assert next(directory.glob("*.png")).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    assert next(directory.glob("*.pdf")).read_bytes().startswith(b"%PDF-")
print(f"Two Pi subagents passed: discovery, isolation, reference, PDF, screenshot; {len(seen)} browser processes stopped. Artifacts: {root}")
