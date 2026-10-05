"""Test the offline OCI filesystem with bubblewrap, or runc in a root VM."""
import hashlib
import http.server
import io
import json
import os
import platform
from pathlib import Path
import pty
import re
import select
import shutil
import socket
import socketserver
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

import zstandard


# Apple Container's OCI defaults, preserved by the inherited procfs sandbox.
APPLE_MASKED_PATHS = [
    "/proc/asound", "/proc/acpi", "/proc/kcore", "/proc/keys",
    "/proc/latency_stats", "/proc/timer_list", "/proc/timer_stats",
    "/proc/sched_debug", "/proc/scsi",
    "/sys/firmware", "/sys/devices/virtual/powercap",
]
APPLE_READONLY_PATHS = ["/proc/bus", "/proc/fs", "/proc/irq", "/proc/sys", "/proc/sysrq-trigger"]


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
            # Avoid keeping multiple copies of the uncompressed layer in RAM.
            with tempfile.TemporaryFile() as unpacked:
                with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(blob(layer))) as source:
                    shutil.copyfileobj(source, unpacked)
                unpacked.seek(0)
                assert "sha256:" + hashlib.file_digest(unpacked, "sha256").hexdigest() == diff
                unpacked.seek(0)
                with tarfile.open(fileobj=unpacked) as content:
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
        if (request.get("tools") and not (self.server.root / marker).exists()
                and not any(message.get("role") == "tool" for message in request["messages"])):
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
python3 - <<'PY'
from pathlib import Path
status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines())
assert status['NoNewPrivs'].strip() == '1'
assert status['Seccomp'].strip() == '2'
assert all(int(status[name], 16) == 0 for name in ('CapEff', 'CapPrm', 'CapBnd', 'CapAmb'))
PY
printf verified > /output/verified
'''}
            events = [
                {"choices": [{"index": 0, "delta": {"role": "assistant", "tool_calls": [{"index": 0, "id": "call_tool", "type": "function", "function": {"name": name, "arguments": json.dumps(arguments)}}]}, "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]},
            ]
        else:
            answer = "offline inference works"
            if "second interactive smoke" in json.dumps(request["messages"]):
                answer += " again"
            events = [
            {"choices": [{"index": 0, "delta": {"role": "assistant", "content": answer}, "finish_reason": None}]},
            {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 10, "completion_tokens": 3}},
            ]
        data = "".join("data: " + json.dumps(event) + "\n\n" for event in events) + "data: [DONE]\n\n"
        self.reply(data.encode(), "text/event-stream")


def main():
    root = Path(sys.argv[2])
    print("Unpacking OCI image", flush=True)
    config = unpack(sys.argv[1], root)
    shutil.copyfile(sys.argv[3], root / "nix/store/pi-proc-isolation.py")
    print("OCI image unpacked", flush=True)
    privileged = os.geteuid() == 0
    home = root.parent / "container-home"
    home.mkdir(mode=0o700)
    state = home / ".pi/agent"
    if privileged:
        # A real root VM can reproduce tmpfs ownership and the UID switch.
        subprocess.run(["mount", "-t", "tmpfs", "-o", "uid=501,gid=100,mode=0700", "tmpfs", str(home)], check=True)
    for directory in ("reference", "output/.git", "unrelated"):
        (root / directory).mkdir(parents=True)
    (root / "reference/marker").write_text("reference\n")
    (root / "output/.git/config").write_text("protected\n")
    (root / "unrelated/secret").write_text("private\n")
    if privileged:
        for path in (root / "output", root / "output/.git", root / "output/.git/config"):
            os.chown(path, 501, 100)

    capabilities = ["CAP_CHOWN", "CAP_SETUID", "CAP_SETGID", "CAP_SYS_CHROOT"] if privileged else []
    command = ["bwrap", "--unshare-all", "--uid", "501", "--gid", "100",
               "--as-pid-1", "--die-with-parent", "--cap-drop", "ALL"]
    command += ["--ro-bind", str(root), "/", "--bind", str(root / "workspace"), "/workspace",
                "--ro-bind", str(root / "reference"), "/reference", "--bind", str(root / "output"), "/output",
                "--bind", str(home), "/home/aldur",
                "--proc", "/proc", "--dev", "/dev", "--perms", "1777", "--tmpfs", "/tmp",
                "--perms", "1777", "--tmpfs", "/var/tmp", "--chdir", "/workspace", "--clearenv"]
    for assignment in config["Env"]:
        key, value = assignment.split("=", 1)
        command += ["--setenv", key, value]
    command += ["--", *config["Entrypoint"]]

    bundle = root.parent / "bundle"
    bundle.mkdir()
    launches = 0

    def launch(*args, caps=capabilities, missing_socket=False, terminal=False,
               masked_proc=True, readonly_proc=True, workspace=True, workdir="/workspace"):
        nonlocal launches
        if not privileged:
            result = command.copy()
            result[result.index("--chdir") + 1] = workdir
            if not workspace:
                index = result.index(str(root / "workspace")) - 1
                del result[index:index + 3]
            if missing_socket:
                index = result.index("--")
                result[index:index] = ["--setenv", "LLAMA_SOCKET_PATH", "/var/host-services/llama.sock"]
            # Reproduce each kind of locked child mount without host root.
            if masked_proc:
                index = result.index("--")
                result[index:index] = ["--ro-bind", "/dev/null", "/proc/keys"]
            if readonly_proc:
                index = result.index("--")
                result[index:index] = ["--ro-bind", "/proc/sys", "/proc/sys"]
            return result + list(args)
        mounts = [
            {"destination": "/proc", "type": "proc", "source": "proc"},
            {"destination": "/dev", "type": "tmpfs", "source": "tmpfs", "options": ["mode=755"]},
            {"destination": "/dev/pts", "type": "devpts", "source": "devpts", "options": ["newinstance", "ptmxmode=0666", "mode=0620"]},
            {"destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["ro"]},
            *({"destination": path, "type": "tmpfs", "source": "tmpfs", "options": ["mode=1777"]}
              for path in ("/tmp", "/var/tmp")),
        ]
        for source, destination, mode in (
            (root / "workspace", "/workspace", "rw"),
            (root / "reference", "/reference", "ro"),
            (root / "output", "/output", "rw"),
            (home, "/home/aldur", "rw"),
        ):
            if destination == "/workspace" and not workspace:
                continue
            mounts.append({"destination": destination, "type": "bind", "source": str(source), "options": ["bind", mode]})
        socket = root / "var/host-services/llama.sock"
        if socket.exists():
            mounts.append({"destination": "/var/host-services/llama.sock", "type": "bind", "source": str(socket), "options": ["bind", "rw"]})
        environment = config["Env"] + (["LLAMA_SOCKET_PATH=/var/host-services/llama.sock"] if missing_socket else [])
        spec = {
            "ociVersion": "1.0.2",
            "root": {"path": str(root), "readonly": True},
            "process": {
                "terminal": terminal,
                "consoleSize": {"height": 24, "width": 80},
                "user": {"uid": 0, "gid": 0}, "cwd": workdir,
                "args": config["Entrypoint"] + list(args), "env": environment,
                "capabilities": {"bounding": caps, "permitted": caps, "effective": caps},
            },
            "mounts": mounts,
            "linux": {
                "namespaces": [{"type": name} for name in ("pid", "network", "ipc", "uts", "mount")],
                "maskedPaths": APPLE_MASKED_PATHS if masked_proc else [path for path in APPLE_MASKED_PATHS if path.startswith("/sys/")],
                "readonlyPaths": APPLE_READONLY_PATHS if readonly_proc else [],
            },
        }
        (bundle / "config.json").write_text(json.dumps(spec))
        launches += 1
        console = ["--detach", "--console-socket", str(bundle / "console.sock")] if terminal else []
        return ["runc", "run", "--bundle", str(bundle), "--no-new-keyring", *console, f"pi-smoke-{launches}"]

    def run(*args, success=True, **options):
        print(f"Running {args[0]}", flush=True)
        result = subprocess.run(launch(*args, **options), stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=180 if privileged else 45)
        if success:
            assert result.returncode == 0, (args[0], result.returncode, result.stdout, result.stderr)
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
import errno, locale, socket, sqlite3, ssl, subprocess, sys, venv
from pathlib import Path
status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines())
assert all(int(status[name], 16) == 0 for name in ('CapEff', 'CapPrm', 'CapAmb')), status
assert int(status['CapBnd'], 16) & ~sum(1 << bit for bit in (0, 6, 7, 18)) == 0, status
for path in ('/etc/passwd', '/bin/unwanted', '/var/unwanted'):
    try:
        Path(path).write_text('unsafe')
    except OSError as error:
        assert error.errno == errno.EROFS, (path, error)
    else:
        raise AssertionError(f'root filesystem is writable: {path}')
assert Path.home().stat().st_mode & 0o777 == 0o700
assert Path.home().stat().st_uid == 501
state = Path.home() / '.pi/agent'
assert not (state / 'keybindings.json').is_symlink()
assert (state / 'keybindings.json').stat().st_mode & 0o777 == 0o600
assert __import__('json').loads((state / 'keybindings.json').read_text())['tui.editor.cursorUp'] == ['up', 'ctrl+p']
assert __import__('json').loads((state / 'settings.json').read_text())['tuiMode'] == 'regular'
assert not (state / 'settings.json').is_symlink()
assert (state / 'settings.json').stat().st_mode & 0o777 == 0o600
(state / 'marker').write_text('preserved')
Path('/tmp/writable').touch()
Path('/var/tmp/writable').touch()
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
    # Nix owns declared keys; undeclared preferences survive later starts.
    custom_keybindings = {"tui.editor.cursorUp": ["ctrl+k"], "app.session.new": ["ctrl+alt+n"]}
    (state / "keybindings.json").write_text(json.dumps(custom_keybindings))
    settings = json.loads((state / "settings.json").read_text())
    settings.update(tuiMode="fullscreen", quietStartup="header")
    (state / "settings.json").write_text(json.dumps(settings))
    run("pi-yolo", "--version")
    run("--version")
    bindings = json.loads((state / "keybindings.json").read_text())
    assert bindings["tui.editor.cursorUp"] == ["up", "ctrl+p"]
    assert bindings["app.session.new"] == ["ctrl+alt+n"]
    settings = json.loads((state / "settings.json").read_text())
    assert settings["tuiMode"] == "regular"
    assert settings["quietStartup"] == "header"
    assert (state / "marker").read_text() == "preserved"
    # Inherited procfs also works when callers clear either set of defaults.
    for masked, readonly in ((True, False), (False, True), (False, False)):
        result = subprocess.run(launch("pi-yolo", "--version", masked_proc=masked, readonly_proc=readonly),
                                stdin=subprocess.DEVNULL, text=True, capture_output=True,
                                timeout=180 if privileged else 45)
        assert result.returncode == 0, (masked, readonly, result.stdout, result.stderr)
    run("python3", "/nix/store/pi-proc-isolation.py")
    run("/bin/bash", "-c", r'''
set -eu
test "$PWD" = "$HOME/workspace"
printf scratch > scratch
pi-yolo --version
python3 - <<'PY'
from pathlib import Path
import subprocess
wrapper = next(Path('/nix/store').glob('*-agent-sandbox/bin/agent-sandbox'))
subprocess.run([str(wrapper), '--profile', 'pi', '--', 'python3', '-c',
                "from pathlib import Path; Path('sandbox-scratch').write_text('sandboxed')"], check=True)
PY
''', workspace=False)
    assert (home / "workspace/scratch").read_text() == "scratch"
    assert (home / "workspace/sandbox-scratch").read_text() == "sandboxed"
    assert not (root / "workspace/scratch").exists()
    # Choosing another directory must not trigger the default-workspace fallback.
    run("/bin/bash", "-c", 'test "$PWD" = /output', workspace=False, workdir="/output")
    if not privileged:
        # A single-UID namespace cannot change from root to UID 501.
        as_root = command.copy()
        as_root[as_root.index("--uid") + 1] = "0"
        as_root[as_root.index("--gid") + 1] = "0"
        failed = subprocess.run(as_root + ["/bin/bash", "-c", "echo UNSAFE_COMMAND"], text=True, capture_output=True, timeout=10)
        assert failed.returncode != 0 and "chroot" in failed.stderr
        assert "UNSAFE_COMMAND" not in failed.stdout
    # Make sure that these commands stop when the required socket is not available.
    failed = subprocess.run(launch("/bin/bash", "-c", "echo UNSAFE_COMMAND", missing_socket=True), stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=10)
    assert failed.returncode != 0 and "inference socket missing" in failed.stderr
    assert "UNSAFE_COMMAND" not in failed.stdout
    with Server(str(root / "var/host-services/llama.sock"), Inference) as server:
        server.root = root
        index = command.index("--")
        command[index:index] = ["--bind", server.server_address, "/var/host-services/llama.sock"]
        if privileged:
            os.chmod(server.server_address, 0o600)
            for capability in capabilities:
                restricted = [cap for cap in capabilities if cap != capability]
                failed = subprocess.run(launch("/bin/bash", "-c", "echo UNSAFE_COMMAND", caps=restricted), stdin=subprocess.DEVNULL, text=True, capture_output=True, timeout=15)
                assert failed.returncode != 0, (capability, failed)
                assert "UNSAFE_COMMAND" not in failed.stdout
                print(f"Missing {capability}: startup failed closed", flush=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = run("/bin/bash", "-c", r'''
set -eu
test "$LLAMA_BASE_URL" = http://127.0.0.1:8080/v1
pi-yolo --models 'llama-cpp/*' -p --no-session --no-tools --no-skills --no-extensions 'say hello'
pi-yolo --models 'llama-cpp/*' -p --no-skills --no-extensions 'create agent.txt'
pi-yolo --ro /reference --rw /output --models 'llama-cpp/*' -p --no-session --no-skills --no-extensions 'check mounts'
# Make sure that both Pi sessions use one relay.
# Make sure that the relay stays available.
test "$(curl -sS "$LLAMA_BASE_URL/large" | wc -c)" = 4194304
''')
            assert "offline inference works" in result.stdout, (result.stdout, result.stderr)
            assert Inference.completion
            assert (root / "workspace/agent.txt").read_text() == "sandboxed task complete\n"
            assert (root / "output/verified").exists(), (result.stdout, result.stderr)
            assert (root / "output/verified").read_text() == "verified"
            assert (root / "reference/marker").read_text() == "reference\n"
            assert (root / "output/.git/config").read_text() == "protected\n"
            assert list((state / "sessions").rglob("*.jsonl")), "Pi session was not saved"

            def interactive_test(*args, failure=None):
                for marker in ("tmux-window-two", "pi-window-exited", "tmux-still-alive", "pi-alternate-screen", "pi-failure-status"):
                    (root / "workspace" / marker).unlink(missing_ok=True)
                if privileged:
                    (bundle / "console.sock").unlink(missing_ok=True)
                # Exercise the entrypoint and the real interactive Pi UI.
                print("Starting interactive Pi", flush=True)
                if privileged:
                    # An OCI terminal is delivered as a PTY descriptor over a socket.
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as console:
                        console.bind(str(bundle / "console.sock"))
                        console.listen(1)
                        console.settimeout(30)
                        interactive = launch(*args, terminal=True)
                        process = subprocess.Popen(interactive, stdin=subprocess.DEVNULL)
                        connection, _ = console.accept()
                        with connection:
                            _, rights, _, _ = connection.recvmsg(1, socket.CMSG_SPACE(4))
                        assert rights[0][:2] == (socket.SOL_SOCKET, socket.SCM_RIGHTS), rights
                        master = int.from_bytes(rights[0][2], sys.byteorder)
                else:
                    master, slave = pty.openpty()
                    process = subprocess.Popen(launch(*args), stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
                    os.close(slave)
                output = bytearray()

                def wait_for(needle=None, *, marker=None):
                    deadline = time.monotonic() + (120 if privileged else 30)
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.2)[0]:
                            try:
                                output.extend(os.read(master, 65536))
                            except OSError:
                                pass
                        plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(output))
                        if ((root / "workspace" / marker).is_file() if marker else needle in plain):
                            return
                        if not privileged and process.poll() is not None:
                            break
                    raise AssertionError((needle, process.poll(), bytes(output[-4000:])))

                try:
                    if failure:
                        wait_for(failure)
                        os.write(master, b"\x01c")
                        os.write(master, b"tmux display-message -p -t :1 '#{pane_dead}:#{pane_dead_status}' > /workspace/pi-failure-status.tmp; and mv /workspace/pi-failure-status.tmp /workspace/pi-failure-status\r")
                        wait_for(marker="pi-failure-status")
                        assert (root / "workspace/pi-failure-status").read_text().strip() == "1:1"
                        os.write(master, b"tmux kill-session\r")
                        assert process.wait(timeout=30) == 0, bytes(output[-4000:])
                        return
                    wait_for(b"clear/exit")
                    os.write(master, b"interactive smoke\r")
                    wait_for(b"offline inference works")
                    # The configured Ctrl-A prefix opens a second window. Its
                    # shell stays outside the agent sandbox and can control tmux.
                    os.write(master, b"\x01c")
                    os.write(master, b"tmux display-message -p -t :1 '#{alternate_on}' > /workspace/pi-alternate-screen.tmp; and mv /workspace/pi-alternate-screen.tmp /workspace/pi-alternate-screen\r")
                    wait_for(marker="pi-alternate-screen")
                    alternate_screen = (root / "workspace/pi-alternate-screen").read_text().strip()
                    assert alternate_screen == "0", f"Pi alternate-screen state: {alternate_screen!r}"
                    os.write(master, b'''test (tmux list-sessions -F '#{session_name}') = 0; and test (tmux display-message -p '#{session_windows}') = 2; and tmux set-hook window-unlinked 'run-shell "touch /workspace/pi-window-exited"'; and tmux select-window -t :1; and printf shell > /workspace/tmux-window-two\r''')
                    wait_for(marker="tmux-window-two")
                    os.write(master, b"second interactive smoke\r")
                    wait_for(b"offline inference works again")
                    os.write(master, b"\x04")
                    wait_for(marker="pi-window-exited")
                    # Pi exits its window, but the second window and container
                    # remain usable. Closing the last shell ends the session.
                    os.write(master, b"printf alive > /workspace/tmux-still-alive; exit\r")
                    wait_for(marker="tmux-still-alive")
                    assert process.wait(timeout=30) == 0, bytes(output[-4000:])
                    if privileged:
                        deadline = time.monotonic() + 30
                        while time.monotonic() < deadline:
                            status = json.loads(subprocess.check_output(["runc", "state", interactive[-1]]))
                            if status["status"] == "stopped":
                                break
                            time.sleep(0.1)
                        else:
                            raise AssertionError("Interactive Pi did not exit")
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    os.close(master)
                    if privileged:
                        subprocess.run(["runc", "delete", "--force", interactive[-1]], check=True)

            interactive_test()
            prompt = "quoted 'argument'; $(touch /workspace/argument-injection)\nsecond line"
            interactive_test("--models", "llama-cpp/*", prompt)
            assert not (root / "workspace/argument-injection").exists()
            interactive_test("--tui-mode", "invalid", failure=b"Invalid TUI mode")
        finally:
            server.shutdown()
    if privileged:
        subprocess.run(["umount", str(home)], check=True)
    print("Finished image: read-only root, Pi state, capabilities, shell, tools and interactive offline Pi passed", flush=True)



if __name__ == "__main__":
    main()
