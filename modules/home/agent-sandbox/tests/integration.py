import os
import errno
import fcntl
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time


def run(*args, **kwargs):
    try:
        return subprocess.run(*args, timeout=20, **kwargs)
    except subprocess.TimeoutExpired as error:
        if error.stderr:
            sys.stderr.write(error.stderr.decode(errors="replace"))
        raise


# Only synthetic values; no ambient host credentials enter these fixtures.
os.environ.update(
    HOST_SECRET="unrelated-secret", DISPLAY=":0", WAYLAND_DISPLAY="wayland-0",
    XAUTHORITY="/home/tester/.Xauthority", GNUPGHOME="/home/tester/Custom GPG",
    GPG_TTY="/dev/host-device", SSH_AGENT_PID="1234", TMUX="/tmp/tmux/default",
    TMUX_PANE="%1", DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket",
    PULSE_SERVER="unix:/run/other-service/socket", PYTHONPATH="/host/python",
    NODE_OPTIONS="--trace-warnings", OPENAI_API_KEY="fixture-openai",
    ANTHROPIC_API_KEY="fixture-anthropic", PROFILE_VALUE="profile value",
    EXPLICIT_VALUE="two words; $(false)\nsecond line", TERM="xterm-256color",
    EDITOR="nvim", VISUAL="nvim -f",
)

runtime = Path(os.environ["XDG_RUNTIME_DIR"])
(runtime / "allowed").mkdir(parents=True)
(runtime / "allowed/marker").write_text("allowed\n")
Path("/tmp/host-marker").write_text("host\n")
sockets = []
for path in [
    Path("/tmp/ssh-advertised/agent"),
    Path("/tmp/ssh-unadvertised/agent"),
    Path(f"/tmp/tmux-{os.getuid()}/default"),
    Path("/tmp/.X11-unix/X0"),
    Path("/run/dbus/system_bus_socket"),
    Path("/run/pcscd/pcscd.comm"),
    Path("/run/other-service/socket"),
    Path("/nix/var/nix/daemon-socket/socket"),
    runtime / "agent",
]:
    path.parent.mkdir(parents=True, exist_ok=True)
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(path))
    sock.listen()
    sockets.append(sock)

wrapper = sys.argv[1]
run(["@seccompProbe@", "baseline"], check=True)

# A generic command does not inherit either agent's state or extra grants.
run([
    wrapper, "--", sys.executable, "-c",
    "from pathlib import Path; import sys, os; "
    "assert sys.argv[1:] == ['two words', '--literal']; "
    "assert not Path('/home/tester/.codex/auth').exists(); "
    "assert not Path('/home/tester/.claude/auth').exists(); "
    "assert not Path('/home/tester/Reference notes/marker').exists(); "
    "assert 'PROFILE_VALUE' not in os.environ; "
    "assert 'HOST_SECRET' not in os.environ; "
    "Path('generic-result').write_text('edited')",
    "two words", "--literal",
], check=True)
assert Path('/home/tester/Work/generic-result').read_text() == 'edited'

# NixOS CA bundles use an intermediate /etc/static path. TLS clients must
# be able to load both conventional names without exposing the rest of it.
run([
    wrapper, "--", sys.executable, "-c",
    "from pathlib import Path; import ssl; "
    "assert not Path('/etc/static/unrelated-secret').exists(); "
    "assert all(ssl.create_default_context(cafile='/etc/ssl/certs/' + name).get_ca_certs() "
    "for name in ('ca-bundle.crt', 'ca-certificates.crt'))",
], check=True)

for args in [[], ["--"], ["--profile", "codex"], ["--profile", "missing", "--", "true"]]:
    result = run([wrapper, *args], capture_output=True)
    assert result.returncode != 0, args

for agent in ["claude", "codex"]:
    launch = [wrapper, "--profile", agent]
    for advertised in [True, False]:
        env = dict(os.environ, TMPDIR="/tmp/missing-host-subdirectory", TEST_AGENT=agent)
        if advertised:
            env["SSH_AUTH_SOCK"] = "/tmp/ssh-advertised/agent"
        else:
            env.pop("SSH_AUTH_SOCK", None)
        completed = run([
            *launch,
            "--ro", "~/Extra reference", "--rw", "~/Extra output",
            "--rw", "~/Work/locked", "--ro", "~/Work/locked",
            "--env", "TEST_AGENT", "--env", "EXPLICIT_VALUE", "--env", "TMPDIR",
            "--", "@probe@",
        ], env=env, capture_output=True, text=True)
        if completed.returncode:
            sys.stderr.write(completed.stdout + completed.stderr)
            completed.check_returncode()
        assert "WARNING" not in completed.stderr
        assert Path("/tmp/host-marker").read_text() == "host\n"
        assert Path("/home/tester/Work/result").read_text() == "edited\n"
        assert Path("/home/tester/.ssh/secret").read_text() == "secret\n"
        assert Path("/home/tester/.local/share/fish/fish_history").read_text() == "history\n"
        assert Path("/home/tester/.config/fish/config.fish").read_text() == "config\n"
        assert not Path("/home/tester/.bashrc").exists()
        assert not Path("/home/tester/.gnupg/sandbox-marker").exists()
        assert Path("/home/tester/.gnupg/private-keys-v1.d/secret.key").read_text() == "private-key-fixture\n"
        assert Path("/home/tester/Custom GPG/secret.key").read_text() == "custom-key-fixture\n"
        assert Path("/home/tester/Shared code/result").read_text() == "edited\n"
        assert Path("/home/tester/Extra output/result").read_text() == "edited\n"
        # The agent state is the host state.
        assert Path(f"/home/tester/.{agent}/sessions/probe-session").read_text() == "session\n"
        if Path("/persist").exists():
            assert Path("/persist/home/tester/Work/result").read_text() == "edited\n"
            assert Path("/persist/system-state").read_text() == "system\n"
        assert not list(Path("/tmp").glob("*-dbus-proxy.*")), "proxy cleanup failed"
        print(f"passed: {agent} profile, SSH_AUTH_SOCK advertised={advertised}", flush=True)

    # Selecting a workspace must not also expose the launch directory.
    run([
        *launch, "--workspace", "/home/tester/Other workspace", "--",
        sys.executable, "-c",
        "from pathlib import Path; "
        "assert not Path('/home/tester/Work/result').exists(); "
        "Path('selected').write_text('edited')",
    ], check=True)
    assert Path("/home/tester/Other workspace/selected").read_text() == "edited"

    # Invalid grants fail before starting a subprocess or the bus proxy.
    for args in [
        ["--workspace", "/"], ["--workspace", "/home/tester"],
        ["--rw", "/persist"], ["--ro", "/home/tester/root-link"],
        ["--rw", "/home/tester/does-not-exist"], ["--ro"],
        ["--env", "INVALID=VALUE"], ["--env", "BAD-NAME"],
    ]:
        result = run([*launch, *args, "--", "true"], capture_output=True)
        assert result.returncode != 0, args

    # Optional built-in mounts also reject symlinks to a broad host root.
    git_config = Path("/home/tester/.config/git")
    git_config.symlink_to("/")
    try:
        result = run([*launch, "--", "true"], capture_output=True, text=True)
        assert result.returncode != 0
        assert "refusing broad filesystem grant" in result.stderr
    finally:
        git_config.unlink()

    help_result = run([wrapper, "--help"], capture_output=True, text=True, check=True)
    for option in ["--profile", "--workspace", "--ro", "--rw", "--env", "--git-write"]:
        assert option in help_result.stdout + help_result.stderr

    print(f"passed: {agent} workspace selection and invalid grants", flush=True)
print("passed: generic command and required command", flush=True)

# The sandbox preserves successful and failed command status and cleans up.
for code in [0, 23]:
    result = run([wrapper, "--", sys.executable, "-c", f"raise SystemExit({code})"], capture_output=True)
    assert result.returncode == code, result.stderr
    assert not list(Path("/tmp").glob("*-dbus-proxy.*"))
result = run([wrapper, "--", "/missing-command"], capture_output=True)
assert result.returncode != 0
assert not list(Path("/tmp").glob("*-dbus-proxy.*"))

# Shell startup injection settings can exist in the caller but must not be
# forwarded to shells started inside the sandbox. This fixture is inert.
startup = Path("/home/tester/Work/startup.sh")
startup.write_text("export STARTUP_WAS_READ=1\n")
result = run([
    wrapper, "--", "@bash@", "-c",
    'test -z "${BASH_ENV+x}" && test -z "${ENV+x}" && test -z "${STARTUP_WAS_READ+x}"',
], env=dict(os.environ, BASH_ENV=str(startup), ENV=str(startup)), capture_output=True)
assert result.returncode == 0, result.stderr

# Exercise a real PTY, including raw input and window-size ioctls. The child
# retains interactive stdio while losing the caller's controlling terminal.
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 100, 0, 0))
terminal_program = '''
import os, termios, tty
assert all(os.isatty(fd) for fd in (0, 1, 2))
assert os.get_terminal_size(0).columns == 100
assert int(open('/proc/self/stat').read().split(') ', 1)[1].split()[4]) == 0
saved = termios.tcgetattr(0)
try:
    tty.setraw(0)
    print('terminal-ready', flush=True)
    assert os.read(0, 1) == b'q'
finally:
    termios.tcsetattr(0, termios.TCSANOW, saved)
print('terminal-passed', flush=True)
'''
def controlling_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)

proc = subprocess.Popen(
    [wrapper, "--", "@python@", "-c", terminal_program],
    stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_terminal,
)
os.close(slave)
output = b""
sent = False
try:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            output += chunk
            if b"terminal-ready" in output and not sent:
                os.write(master, b"q")
                sent = True
        elif proc.poll() is not None:
            break
    assert proc.wait(timeout=2) == 0, output
    assert b"terminal-passed" in output, output
finally:
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    os.close(master)
assert not list(Path("/tmp").glob("*-dbus-proxy.*"))
print("passed: exit status, shell environment and interactive terminal", flush=True)

# Ctrl-C in a canonical terminal must also end a command in the new session,
# and its proxy. Do not leave a detached command waiting after the user exits.
master, slave = pty.openpty()
proc = subprocess.Popen(
    [wrapper, "--", "@python@", "-c", "import time; print('interrupt-ready', flush=True); time.sleep(60)"],
    stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_terminal,
)
os.close(slave)
output = b""
try:
    deadline = time.monotonic() + 20
    while b"interrupt-ready" not in output and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            output += os.read(master, 65536)
    assert b"interrupt-ready" in output, output
    os.write(master, b"\x03")
    assert proc.wait(timeout=3) in (130, -signal.SIGINT), output
finally:
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    os.close(master)
assert not list(Path("/tmp").glob("*-dbus-proxy.*"))
print("passed: terminal interrupt and cleanup", flush=True)

# Failure to install the filter must prevent the requested command from
# executing, rather than silently losing a layer of protection.
marker = Path("/home/tester/Work/should-not-run")
with open("@unavailableSeccomp@", "rb") as policy:
    result = run([
        "@bwrap@", "--bind", "/", "/", "--dev", "/dev",
        "--seccomp", str(policy.fileno()), "--",
        wrapper, "--", "@python@", "-c", f"from pathlib import Path; Path({str(marker)!r}).touch()",
    ], pass_fds=(policy.fileno(),), capture_output=True, text=True)
assert result.returncode != 0
assert "SECCOMP" in result.stderr, result.stderr
assert not marker.exists()
assert not list(Path("/tmp").glob("*-dbus-proxy.*"))
print("passed: unavailable seccomp fails closed", flush=True)

# Synthetic session services prove the proxy admits configured names and
# denies an existing service outside the allowlist.
def bus_call(name):
    return [
        "@dbusSend@", "--session", "--print-reply", "--reply-timeout=2000",
        f"--dest={name}", "/org/example/Test", "org.example.Test.Ping",
    ]

services = []
try:
    for name in ["org.example.Allowed", "org.example.Hidden"]:
        services.append(subprocess.Popen(["@dbusTestTool@", "echo", "--session", f"--name={name}"]))
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            result = run(bus_call(name), capture_output=True)
            if result.returncode == 0:
                break
            time.sleep(0.05)
        assert result.returncode == 0, result.stderr
    for agent in ["codex", "claude"]:
        result = run([wrapper, "--profile", agent, "--", *bus_call("org.example.Allowed")], capture_output=True)
        assert result.returncode == 0, result.stderr
        result = run([wrapper, "--profile", agent, "--", *bus_call("org.example.Hidden")], capture_output=True)
        assert result.returncode != 0
finally:
    for service in services:
        service.terminate()
        service.wait(timeout=5)
assert not list(Path("/tmp").glob("*-dbus-proxy.*"))
print("passed: session bus allowlist", flush=True)

# Extra descriptors must not provide access to an otherwise hidden file.
with open("/home/tester/Unrelated/secret", "rb") as secret:
    result = run([
        wrapper, "--", "@python@", "-c",
        "import os; from pathlib import Path; "
        "assert all('Unrelated/secret' not in os.readlink(p) "
        "for p in Path('/proc/self/fd').iterdir() if p.exists())",
    ], pass_fds=(secret.fileno(),), capture_output=True)
assert result.returncode == 0, result.stderr
print("passed: inherited descriptors closed", flush=True)

# This suite launches many individually bounded commands; allow slower target
# kernels enough time for the group, including concurrent-wrapper checks.
subprocess.run([sys.executable, "@metadataTests@", wrapper], check=True, timeout=120)
subprocess.run([sys.executable, "@direnvTests@", wrapper], check=True, timeout=120)
