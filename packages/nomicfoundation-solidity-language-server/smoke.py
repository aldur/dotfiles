"""Check the deployed dependencies and the server's stdio LSP transport."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys


package = Path(sys.argv[1])
subprocess.run(
    ["node", "--input-type=module", "-e", """
      import assert from 'node:assert/strict';
      import { createRequire } from 'node:module';
      const require = createRequire(process.cwd() + '/package.json');
      const { analyze } = require('@nomicfoundation/solidity-analyzer');
      assert.deepEqual(analyze('pragma solidity ^0.8.0; contract Probe {}').imports, []);
      const { Parser } = await import('@nomicfoundation/slang/parser');
      assert.ok(Parser.create('0.8.0'));
    """],
    cwd=package / "lib/solidity-language-server",
    check=True,
    timeout=30,
)

# Upstream's test mode avoids fetching the compiler version list on initialize.
env = {**os.environ, "VSCODE_NODE_ENV": "development"}
proc = subprocess.Popen(
    [str(package / "bin/nomicfoundation-solidity-language-server"), "--stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    env=env,
)


def timeout(_signum, _frame):
    raise TimeoutError("language server did not respond")


def send(message):
    body = json.dumps({"jsonrpc": "2.0", **message}).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()


def request(request_id, method, params):
    send(dict(id=request_id, method=method, params=params))
    while True:
        headers = {}
        while (line := proc.stdout.readline()) != b"\r\n":
            assert line, f"server exited: {proc.poll()}"
            key, value = line.decode().split(":", 1)
            headers[key.lower()] = value.strip()
        reply = json.loads(proc.stdout.read(int(headers["content-length"])))
        if reply.get("id") == request_id:
            assert "error" not in reply, reply
            return reply["result"]


signal.signal(signal.SIGALRM, timeout)
signal.alarm(30)
try:
    result = request(1, "initialize", dict(
        processId=None, rootUri=None, workspaceFolders=[],
        capabilities={}, initializationOptions={"telemetryEnabled": False},
    ))
    assert result["capabilities"]["documentFormattingProvider"], result
    send(dict(method="initialized", params={}))
    request(2, "shutdown", None)
    send(dict(method="exit"))
    assert proc.wait(timeout=5) == 0
finally:
    signal.alarm(0)
    if proc.poll() is None:
        proc.kill()
    proc.wait()

print("PASS: native analyzer, Slang, LSP initialization and shutdown")
