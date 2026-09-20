import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

pandoc, pi, rga = sys.argv[1:]

Path("document.md").write_text("# Runtime check\n\nA **bold** word and café.\n")
Path("filter.lua").write_text('''
package.cpath = "./?.so;" .. package.cpath
assert(require("native") == "native module loaded")
assert(require("lpeg").match(require("lpeg").P("ok"), "ok") == 3)
function Strong(el)
  return pandoc.Emph(el.content)
end
''')
html = subprocess.check_output(
    [pandoc, "document.md", "--lua-filter=filter.lua", "-t", "html"], text=True
)
assert "<em>bold</em>" in html and "café" in html, html
for fmt in ("docx", "odt", "epub"):
    output = f"document.{fmt}"
    subprocess.run([pandoc, "document.md", "-o", output], check=True)
    plain = subprocess.check_output([pandoc, output, "-t", "plain"], text=True)
    assert "Runtime check" in plain and "café" in plain, plain
    found = subprocess.check_output([rga, "--rga-adapters=pandoc", "café", output], text=True)
    assert "café" in found, found

# Load a TypeScript extension through jiti and import the SDK used by user
# extensions. RPC exercises startup without an API key or an inference call.
Path("extension.ts").write_text('''
import { getModel } from "@earendil-works/pi-ai";
import { createReadTool } from "@earendil-works/pi-coding-agent";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
export default function(pi: ExtensionAPI) {
  if (!getModel("anthropic", "claude-sonnet-4-5")) throw new Error("missing SDK model");
  if (typeof createReadTool !== "function") throw new Error("missing SDK tool");
  pi.registerCommand("runtime-check", {
    description: "runtime check loaded",
    handler: async () => {},
  });
}
''')
env = os.environ | {"PI_OFFLINE": "1", "PI_TELEMETRY": "0"}
with open("pi-stderr.log", "w+") as errors:
    proc = subprocess.Popen(
        [pi, "--offline", "--mode", "rpc", "--no-session", "--no-context-files",
         "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes",
         "-e", str(Path("extension.ts").resolve())],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, env=env,
    )
    try:
        requests = ("get_state", "get_commands", "get_available_models")
        for command in requests:
            proc.stdin.write((json.dumps({"type": command, "id": command}) + "\n").encode())
        proc.stdin.flush()
        replies = {}
        deadline = time.monotonic() + 45
        pending = b""
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while len(replies) < len(requests):
                remaining = deadline - time.monotonic()
                assert remaining > 0, f"RPC timed out: {replies}"
                assert selector.select(remaining), f"RPC timed out: {replies}"
                chunk = os.read(proc.stdout.fileno(), 65536)
                assert chunk, f"Pi exited early: {proc.poll()}"
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    event = json.loads(line)
                    if event.get("type") == "response" and event.get("id") in requests:
                        assert event["success"], event
                        replies[event["id"]] = event["data"]
        commands = replies["get_commands"]["commands"]
        assert any(c["name"] == "runtime-check" for c in commands), commands
        assert any(c["name"] == "system-prompt" for c in commands), commands
        # With no credentials configured, the available-model list can be empty.
        assert isinstance(replies["get_available_models"]["models"], list), replies
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        errors.seek(0)
        print(errors.read())
print("Pandoc converters, native Lua filters, rga, and Pi extensions passed")
