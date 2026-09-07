"""Run inside the sandbox; all host endpoints belong to the outer fixture."""
import errno
import os
from pathlib import Path
import socket
import subprocess


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=15, **kwargs)


for name in (
    "HOST_SECRET", "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "GPG_TTY",
    "SSH_AUTH_SOCK", "SSH_AGENT_PID", "TMUX", "TMUX_PANE",
    "DBUS_SYSTEM_BUS_ADDRESS", "PULSE_SERVER", "BASH_ENV", "ENV",
    "PYTHONPATH", "NODE_OPTIONS", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
):
    assert name not in os.environ, name
assert os.environ["EXPLICIT_VALUE"] == "two words; $(false)\nsecond line"
assert os.environ["PROFILE_VALUE"] == "profile value"
assert os.environ["TERM"] == "xterm-256color"
assert os.environ["TMPDIR"] == "/tmp"

for name in (
    "/run/dbus/system_bus_socket", "/run/pcscd/pcscd.comm",
    "/tmp/.X11-unix/X0", "/tmp/ssh-advertised/agent",
    "/tmp/ssh-unadvertised/agent", "/run/other-service/socket",
):
    assert not Path(name).exists(), name
    with socket.socket(socket.AF_UNIX) as client:
        try:
            client.connect(name)
        except OSError as error:
            assert error.errno == errno.ENOENT, (name, error)
        else:
            raise AssertionError(f"host socket reachable: {name}")
assert not Path("/dev/host-device").exists()
assert not Path("/dev/dri").exists()
assert not Path("/sys").exists()
assert Path("/dev/null").is_char_device()
assert Path("/dev/urandom").is_char_device()
assert len(os.urandom(16)) == 16

# GPG may start a new agent, but its home must be private and usable.
gnupg = Path(os.environ["GNUPGHOME"])
assert gnupg == Path.home() / ".gnupg"
assert gnupg.stat().st_mode & 0o777 == 0o700
assert not (gnupg / "private-keys-v1.d/secret.key").exists()
assert not (Path.home() / "Custom GPG/secret.key").exists()
run("@gpg@", "--batch", "--list-keys", capture_output=True)
(gnupg / "sandbox-marker").write_text("ephemeral")

status = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines())
assert status["NoNewPrivs"].strip() == "1"
assert status["Seccomp"].strip() == "2"
assert int(status["CapEff"], 16) == 0
assert int(Path("/proc/self/stat").read_text().split(") ", 1)[1].split()[4]) == 0, "host controlling TTY retained"
run("@seccompProbe@")
# A grandchild must inherit the filter too.
run("@bash@", "-c", 'exec "$1"', "probe", "@seccompProbe@")

# Normal development still supports subprocesses, pipes, Git and an inner
# bubblewrap sandbox. Repository metadata has separate integration coverage.
run("@bash@", "-c", "printf hello | cat > pipe-result")
assert Path("pipe-result").read_text() == "hello"
run("@bwrap@", "--ro-bind", "/", "/", "--unshare-pid", "--", "@bash@", "-c", "true")

daemon = Path("/nix/var/nix/daemon-socket/socket")
if os.environ["TEST_AGENT"] == "codex":
    assert daemon.is_socket()
    assert os.environ["NIX_REMOTE"] == "daemon"
else:
    assert not daemon.exists()
    assert "NIX_REMOTE" not in os.environ
