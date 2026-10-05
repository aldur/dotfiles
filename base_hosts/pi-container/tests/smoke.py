"""Do a test of the OCI filesystem in a user namespace with no external network access."""
import hashlib
import http.server
import io
import json
import os
import platform
from pathlib import Path
import socketserver
import subprocess
import sys
import tarfile
import threading

import zstandard


def unpack(archive_path, root):
    root.mkdir(parents=True)
    with tarfile.open(archive_path) as archive:
        def member(name):
            try:
                return archive.extractfile(name)
            except KeyError:
                return archive.extractfile("./" + name)

        def blob(descriptor):
            data = member("blobs/" + descriptor["digest"].replace(":", "/")).read()
            assert len(data) == descriptor["size"]
            assert "sha256:" + hashlib.sha256(data).hexdigest() == descriptor["digest"]
            return data

        index = json.load(member("index.json"))
        manifest = json.loads(blob(index["manifests"][0]))
        assert manifest["mediaType"] == "application/vnd.oci.image.manifest.v1+json"
        assert manifest["config"]["mediaType"] == "application/vnd.oci.image.config.v1+json"
        config = json.loads(blob(manifest["config"]))
        assert config["os"] == "linux"
        assert config["architecture"] == {"x86_64": "amd64", "aarch64": "arm64"}[platform.machine()]
        for layer, diff in zip(manifest["layers"], config["rootfs"]["diff_ids"], strict=True):
            assert layer["mediaType"] == "application/vnd.oci.image.layer.v1.tar+zstd"
            with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(blob(layer))) as source:
                # Make sure that the diff ID and the blob digest are correct.
                unpacked = source.read()
            assert "sha256:" + hashlib.sha256(unpacked).hexdigest() == diff
            with tarfile.open(fileobj=io.BytesIO(unpacked)) as content:
                for entry in content:
                    entry.name = entry.name.removeprefix("./").lstrip("/")
                    assert ".." not in Path(entry.name).parts
                    if entry.islnk():
                        entry.linkname = entry.linkname.removeprefix("./").lstrip("/")
                    if entry.name.rstrip("/").removeprefix("./") in ("home/aldur", "workspace"):
                        assert (entry.uid, entry.gid) == (501, 100)
                content.extractall(root, filter="fully_trusted")
        return config["config"]


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


class Inference(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    completion = False

    def log_message(self, *args):
        pass

    def reply(self, data, content_type="application/json"):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/v1/large":
            self.reply(b"x" * (4 * 1024 * 1024), "text/plain")
            return
        if self.path == "/v1/models":
            data = {"data": [{"id": "local", "status": {"value": "loaded"}, "meta": {"n_ctx": 65536}}]}
        elif self.path.startswith("/props"):
            data = {"chat_template": "{{ messages }}", "default_generation_settings": {"n_ctx": 65536}}
        else:
            self.send_error(404)
            return
        self.reply(json.dumps(data).encode())

    def do_POST(self):
        assert self.path == "/v1/chat/completions", self.path
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert request["model"] == "local"
        Inference.completion = True
        mounts = "check mounts" in json.dumps(request["messages"])
        marker = "output/verified" if mounts else "workspace/agent.txt"
        if request.get("tools") and not (self.server.root / marker).exists():
            name = "write"
            arguments = {"path": "/workspace/agent.txt", "content": "sandboxed task complete\n"}
            if mounts:
                name = "bash"
                arguments = {"command": r'''
set -eu
git -C /workspace/repository status --porcelain
test "$(cat /reference/marker)" = reference
test ! -e /unrelated/secret
if printf changed > /reference/marker; then exit 1; fi
for metadata in /workspace/repository/.git /output/.git; do
  test -r "$metadata/config"
  if printf changed > "$metadata/config"; then exit 1; fi
  if touch "$metadata/new"; then exit 1; fi
  if mv "$metadata" "$metadata.moved"; then exit 1; fi
done
printf verified > /output/verified
'''}
            events = [
                {"choices": [{"index": 0, "delta": {"role": "assistant", "tool_calls": [{"index": 0, "id": "call_tool", "type": "function", "function": {"name": name, "arguments": json.dumps(arguments)}}]}, "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]},
            ]
        else:
            events = [
            {"choices": [{"index": 0, "delta": {"role": "assistant", "content": "offline inference works"}, "finish_reason": None}]},
            {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 10, "completion_tokens": 3}},
            ]
        data = "".join("data: " + json.dumps(event) + "\n\n" for event in events) + "data: [DONE]\n\n"
        self.reply(data.encode(), "text/event-stream")


def main():
    root = Path(sys.argv[2])
    config = unpack(sys.argv[1], root)
    command = ["bwrap", "--unshare-all", "--as-pid-1", "--die-with-parent", "--uid", "501", "--gid", "100",
               "--bind", str(root), "/", "--ro-bind", str(root / "nix/store"), "/nix/store",
               "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--chdir", "/workspace", "--clearenv"]
    for assignment in config["Env"]:
        key, value = assignment.split("=", 1)
        command += ["--setenv", key, value]
    command += ["--", *config["Entrypoint"]]

    def run(*args, success=True):
        result = subprocess.run(command + list(args), text=True, capture_output=True, timeout=45)
        if success:
            assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
        else:
            assert result.returncode != 0, args
        return result

    smoke = r'''
set -eu
test "$(id -u)" = 501
test "$PWD" = /workspace
test ! -e /sbin/init
for absent in nix pnpm npm claude codex llm llama-server gcc; do
  if command -v "$absent"; then exit 1; fi
done
test -z "${LLAMA_SOCKET_PATH-}"
test "$(ls /sys/class/net 2>/dev/null | wc -l)" -le 1
python3 - <<'PY'
import locale, socket, sqlite3, ssl, subprocess, sys, venv
assert sys.stdout.encoding.lower() == 'utf-8'
assert sqlite3.connect(':memory:').execute('select 42').fetchone() == (42,)
assert 'é'.encode().decode() == 'é'
try:
    socket.create_connection(('1.1.1.1', 443), timeout=.2)
except OSError:
    pass
else:
    raise AssertionError('external network is reachable')
venv.create('/workspace/venv', with_pip=True)
subprocess.run(['/workspace/venv/bin/python', '-m', 'pip', '--version'], check=True)
PY
fish -lic 'functions -q fish_hybrid_key_bindings; and functions -q gw; and functions -q lg; and command -q zoxide; and command -q fzf'
pi --version
pi-yolo --version
git init -q repository
cd repository
printf 'hello\n' > file
git add file
git commit -qm initial
git status --porcelain | grep -q '^$' || test -z "$(git status --porcelain)"
cd /workspace
lazyvim --headless '+lua local ok, err = pcall(function() assert(require("nixCats").cats.general); assert(not require("nixCats").cats.ide); require("lazy").load({plugins={"nvim-treesitter"}}); assert(vim.treesitter.language.add("python")); assert(vim.treesitter.query.get("python", "highlights")) end); if not ok then io.stderr:write(tostring(err)); vim.cmd("cquit 1") else vim.cmd("qa!") end'
printf 'changed\n' > document
lazyvim --headless document '+normal! Goedited' +wq
grep -q edited document
printf 'abc\n' | sponge result
test "$(cat result)" = abc
printf 'abc\n' | ts '%Y' | grep -q abc
printf 'abc\n' | pee 'cat > one' 'cat > two'
cmp one two
chronic true
tmux -L smoke new-session -d
tmux -L smoke kill-server
for tool in bat btop htop curl dig fd file jq less pv rg tmux age tree totp-cli direnv lazygit; do command -v "$tool"; done
'''
    result = run("/bin/bash", "-c", smoke)
    print(result.stdout)
    # This namespace maps only one UID. It cannot change the UID to 501.
    # If the entrypoint cannot change the UID, make sure that it stops before the command.
    as_root = command.copy()
    as_root[as_root.index("--uid") + 1] = "0"
    as_root[as_root.index("--gid") + 1] = "0"
    failed = subprocess.run(as_root + ["/bin/bash", "-c", "echo UNSAFE_COMMAND"], text=True, capture_output=True, timeout=10)
    assert failed.returncode != 0 and "chroot" in failed.stderr
    assert "UNSAFE_COMMAND" not in failed.stdout
    # Make sure that these commands stop when the required socket is not available.
    missing = command.copy()
    missing[missing.index("--"):missing.index("--")] = ["--setenv", "LLAMA_SOCKET_PATH", "/var/host-services/llama.sock"]
    failed = subprocess.run(missing + ["/bin/bash", "-c", "echo UNSAFE_COMMAND"], text=True, capture_output=True, timeout=10)
    assert failed.returncode != 0 and "inference socket missing" in failed.stderr
    assert "UNSAFE_COMMAND" not in failed.stdout
    for directory in ("reference", "output/.git", "unrelated"):
        (root / directory).mkdir(parents=True)
    (root / "reference/marker").write_text("reference\n")
    (root / "output/.git/config").write_text("protected\n")
    (root / "unrelated/secret").write_text("private\n")
    with Server(str(root / "var/host-services/llama.sock"), Inference) as server:
        server.root = root
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = run("/bin/bash", "-c", r'''
set -eu
test "$LLAMA_BASE_URL" = http://127.0.0.1:8080/v1
pi-yolo --models 'llama-cpp/*' -p --no-session --no-tools --no-skills --no-extensions 'say hello'
pi-yolo --models 'llama-cpp/*' -p --no-session --no-skills --no-extensions 'create agent.txt'
pi-yolo --ro /reference --rw /output --models 'llama-cpp/*' -p --no-session --no-skills --no-extensions 'check mounts'
# Make sure that both Pi sessions use one relay.
# Make sure that the relay stays available.
test "$(curl -sS "$LLAMA_BASE_URL/large" | wc -c)" = 4194304
''')
            assert "offline inference works" in result.stdout, (result.stdout, result.stderr)
            assert Inference.completion
            assert (root / "workspace/agent.txt").read_text() == "sandboxed task complete\n"
            assert (root / "output/verified").read_text() == "verified"
            assert (root / "reference/marker").read_text() == "reference\n"
            assert (root / "output/.git/config").read_text() == "protected\n"
        finally:
            server.shutdown()
    print("Finished image: shell, CLI, Git, Python, editor, tmux and offline Pi tool execution passed")



if __name__ == "__main__":
    main()
