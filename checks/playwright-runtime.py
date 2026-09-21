"""Exercise the packaged MCP with the same browser flags as Home Manager."""

import http.server
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import threading
import time


command = Path(sys.argv[1])
wrapper = command.read_text()
farm = Path(re.search(r"PLAYWRIGHT_BROWSERS_PATH='([^']+)'", wrapper)[1])
assert len(list(farm.glob("chromium_headless_shell-*"))) == 1
assert not any(farm.glob("chromium-*")), "full Chromium returned"
assert not any(farm.glob("firefox-*")) and not any(farm.glob("webkit-*"))
assert {p.name for p in farm.glob("**/locales/*.pak")} == {"en-US.pak"}

output = Path("output").resolve()
output.mkdir()
(output / "upload.txt").write_text("upload fixture")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        if self.path == "/download":
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="fixture.txt"')
            body = b"download fixture"
        else:
            self.send_header("Content-Type", "text/html")
            body = b'''<title>Browser check</title><h1>Headless runtime</h1>
              <button onclick="this.textContent='Clicked'">Click me</button>
              <a href="/download">Download</a><input type="file">'''
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
with Path("mcp-stderr.log").open("w+") as errors:
    # No executable override or font configuration: test the package defaults.
    proc = subprocess.Popen(
        [str(command), "--headless", "--isolated", "--output-dir", str(output)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
    )
    sequence = 0
    pending = b""

    def rpc(method, params):
        global sequence, pending
        sequence += 1
        request = dict(jsonrpc="2.0", id=sequence, method=method, params=params)
        proc.stdin.write((json.dumps(request) + "\n").encode())
        proc.stdin.flush()
        deadline = time.monotonic() + 45
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    reply = json.loads(line)
                    if reply.get("id") == sequence:
                        assert "error" not in reply, reply
                        result = reply["result"]
                        assert not result.get("isError"), result
                        return result
                remaining = deadline - time.monotonic()
                assert remaining > 0 and selector.select(remaining), f"timeout: {method}"
                chunk = os.read(proc.stdout.fileno(), 65536)
                assert chunk, f"MCP exited: {proc.poll()}"
                pending += chunk

    def call(name, **arguments):
        return rpc("tools/call", dict(name=name, arguments=arguments))

    try:
        rpc("initialize", dict(protocolVersion="2024-11-05", capabilities={},
                               clientInfo=dict(name="runtime-check", version="1")))
        proc.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        proc.stdin.flush()
        call("browser_navigate", url=f"http://127.0.0.1:{server.server_port}/")
        snapshot = max(output.glob("page-*.yml"), key=lambda p: p.stat().st_mtime_ns).read_text()
        assert "Headless runtime" in snapshot, snapshot
        paths = json.dumps({name: str(output / name) for name in
                            ("upload.txt", "download.txt", "page.pdf")})
        call("browser_run_code", code="""async (page) => {
          const paths = """ + paths + """;
          await page.getByRole('button', {name: 'Click me'}).click();
          if (await page.locator('button').textContent() !== 'Clicked')
            throw new Error('click failed');
          const waiting = page.waitForEvent('download');
          await page.getByText('Download', {exact: true}).click();
          const download = await waiting;
          if (download.suggestedFilename() !== 'fixture.txt') throw new Error('filename');
          await download.saveAs(paths['download.txt']);
          await page.locator('input').setInputFiles(paths['upload.txt']);
          if (await page.locator('input').evaluate(el => el.files[0].text()) !== 'upload fixture')
            throw new Error('upload failed');
          await page.evaluate(() => {
            localStorage.setItem('audit', 'retained');
            document.cookie = 'audit=retained; SameSite=Lax';
          });
          await page.reload();
          if (!await page.evaluate(() => localStorage.getItem('audit') === 'retained'
              && document.cookie === 'audit=retained')) throw new Error('storage failed');
          await page.pdf({path: paths['page.pdf']});
        }""")
        assert (output / "download.txt").read_text() == "download fixture"
        assert (output / "page.pdf").read_bytes().startswith(b"%PDF-")
        call("browser_take_screenshot", type="png", filename=str(output / "page.png"))
        assert (output / "page.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
        call("browser_close")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        server.shutdown()
        errors.seek(0)
        print(errors.read())

print("Headless MCP: navigation, snapshot, click, files, storage, PDF and PNG passed")
