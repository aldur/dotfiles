"""Boot a live guest through the qemu-vm launcher and probe its sandbox.

Every scenario boots the guest on the serial console, runs a few busybox
commands in it, pokes the host side, and collects the sandbox denials the
unified log reports for the two processes. A denial outside the known
benign set fails the scenario: the profiles allow what the processes need
and nothing more, so a new denial is either a broken feature or a rule
that is no longer needed.

The guest is an Alpine live ISO. The checks use only what its busybox
has: udhcpc, nslookup, wget, nc.
"""

import argparse
import http.server
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

import pexpect

GUEST_IP = "192.168.127.2"
GATEWAY_IP = "192.168.127.1"
# gvproxy's default mapping of the host loopback, which the launcher turns off.
HOST_VIRTUAL_IP = "192.168.127.254"
GUEST_PORT = 8080
FORWARD_PORT = 18080
LOOPBACK_SERVER_PORT = 18765
ANY_SERVER_PORT = 18766
SERVER_MARKER = "host-http-marker"
PROMPT = "localhost:~# "
# Colours and cursor queries the guest's shell writes to the pty.
ESCAPES = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

# Denials the two processes are known to survive; see the comment block
# above the profiles in qemu-vm.nix.
BENIGN_DENIALS = [
    r"mach-lookup com\.apple\.(diagnosticd|logd|analyticsd|tccd\.system|system\.notification_center)",
    r"mach-lookup com\.apple\.(DiskArbitration|system\.opendirectoryd|dock\.fullscreen)",
    r"mach-lookup com\.apple\.(bsd\.dirhelper|uiintelligencesupport)",
    # Cocoa, non-fatal: the window shows and works without them
    r"mach-lookup com\.apple\.(CoreServices\.coreservicesd|coreservices\.appleevents|ViewBridgeAuxiliary)",
    r"mach-lookup com\.apple\.(distributed_notifications|dock\.server|touchbarserver|window_proxies)",
    r"mach-register com\.apple\.(tsm\.portname|coredrag|axserver)",
    r"file-read-data /dev/dtracehelper",
    r"file-read-data /System/Library/CoreServices/SystemVersion\.plist",
    r"file-read-data /(System/)?Library/Preferences/",
    r"file-read-data /private/var/db/eligibilityd/",
    r"file-read-data /usr/lib$",
    r"file-read-data /Users/[^/]+/Library/(Autosave Information|Keyboard Layouts|Input Methods)",
    # stat only reveals that a path exists
    r"file-read-metadata ",
    r"sysctl-read kern\.(osproductversion|osvariant_status|iossupportversion|hv_vmm_present|willshutdown)",
    r"sysctl-read kern\.(ipc\.somaxconn|maxfilesperproc)",
    r"sysctl-read hw\.(ephemeral_storage|physicalcpu_max|logicalcpu_max)",
    # gvproxy: Go's CPU feature detection; QEMU gets the prefix allowed
    r"gvproxy\S* deny\(1\) sysctl-read hw\.optional\.",
    r"system-socket domain:32",
    r"network-outbound /private/var/run/syslog",
    r"user-preference-read com\.apple\.hitoolbox",
    # the GPU stays denied; Cocoa renders in software
    r"iokit-open-user-client AGXDeviceUserClient",
]
# Denials that specific probes provoke on purpose.
PROVOKED_DENIALS = [
    r"gvproxy\S* deny\(1\) network-outbound remote:",
    r"qemu-system\S* deny\(1\) process-fork",
]


class Failure(Exception):
    pass


def log(message):
    print(message, flush=True)


def lan_ip():
    """The address of the interface that routes to the internet, or None."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("1.1.1.1", 53))
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = SERVER_MARKER.encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def serve(address, port):
    server = http.server.ThreadingHTTPServer((address, port), MarkerHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class Denials:
    """Sandbox denials of the two processes, from the unified log."""

    def __init__(self):
        self.file = tempfile.NamedTemporaryFile("w+", prefix="denials.", suffix=".log")
        self.process = subprocess.Popen(
            [
                "/usr/bin/log",
                "stream",
                "--style",
                "compact",
                "--predicate",
                'sender == "Sandbox" AND (eventMessage CONTAINS "qemu-system" OR eventMessage CONTAINS "gvproxy")',
            ],
            stdout=self.file,
            stderr=subprocess.STDOUT,
        )
        time.sleep(2)

    def stop(self):
        time.sleep(2)
        self.process.terminate()
        self.process.wait()
        self.file.seek(0)
        lines = []
        for line in self.file:
            m = re.search(r"Sandbox: (\S+)\(\d+\) (deny\(\d\) .*)$", line.rstrip())
            if m:
                lines.append(f"{m.group(1)} {m.group(2)}")
        self.file.close()
        return sorted(set(lines))


def unexpected(denials):
    patterns = [re.compile(p) for p in BENIGN_DENIALS + PROVOKED_DENIALS]
    return [d for d in denials if not any(p.search(d) for p in patterns)]


class Guest:
    """The launcher on a pty, with root logged in on the serial console."""

    def __init__(self, launcher, args, timeout=240):
        self.child = pexpect.spawn(launcher, args, encoding="utf-8", timeout=timeout)
        self.monitor = None
        self.exit_status = None
        while True:
            i = self.child.expect([r"Monitor: nc -U (\S+)", r"login: ", pexpect.EOF])
            if i == 0:
                self.monitor = self.child.match.group(1)
            elif i == 1:
                break
            else:
                raise Failure("the launcher exited before the login prompt:\n" + self.child.before[-2000:])
        self.child.sendline("root")
        self.child.expect(PROMPT)
        self.child.timeout = 60

    def run(self, command):
        """Run a command in the guest; return its output and exit status."""
        # A background command ends in `&`, which already terminates the list.
        separator = " " if command.rstrip().endswith("&") else "; "
        self.child.sendline(f"{command}{separator}echo RC=$?")
        self.child.expect(PROMPT)
        out = ESCAPES.sub("", self.child.before.replace("\r", ""))
        m = re.search(r"^RC=(\d+)$", out, re.M)
        rc = int(m.group(1)) if m else -1
        # drop the echoed command line and the RC line
        lines = [line for line in out.split("\n")[1:] if not line.startswith("RC=")]
        return "\n".join(lines).strip(), rc

    def poweroff(self):
        self.child.sendline("poweroff")
        self.child.expect(pexpect.EOF, timeout=120)
        self.child.close()
        self.exit_status = self.child.exitstatus
        return self.child.before.replace("\r", "")


def monitor_command(path, command):
    """Send one HMP command; return the reply, without the echoed keystrokes."""
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(1)
    s.connect(path)
    time.sleep(0.3)
    s.recv(4096)
    s.sendall((command + "\n").encode())
    # The monitor echoes each keystroke with cursor movements, then prints
    # the reply and a new prompt.
    out = b""
    deadline = time.time() + 10
    while b"(qemu) " not in out and time.time() < deadline:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        out += chunk
    s.close()
    text = ESCAPES.sub("", out.decode(errors="replace")).replace("\r", "")
    return text.split("\n", 1)[1] if "\n" in text else ""


def http_get(url, timeout=5):
    import urllib.request

    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.read().decode(errors="replace")
    except Exception as e:  # noqa: BLE001
        return f"ERROR {e.__class__.__name__}"


def qemu_windows():
    import Quartz

    infos = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    return [w for w in infos if "qemu" in str(w.get("kCGWindowOwnerName", "")).lower()]


def listening_sockets(process_name):
    script = (
        f"lsof -a -p $(pgrep -x {process_name}) -i -P -n -sTCP:LISTEN 2>/dev/null"
        " | grep -v COMMAND | awk '{print $9}'"
    )
    out = subprocess.run(["sh", "-c", script], capture_output=True, text=True).stdout
    return sorted(set(out.split()))


class Scenario:
    def __init__(self, name):
        self.name = name
        self.results = []

    def check(self, what, ok, detail=""):
        self.results.append((what, bool(ok), detail))
        mark = "ok  " if ok else "FAIL"
        log(f"  {mark} {what}" + (f"  [{detail}]" if detail and not ok else ""))

    @property
    def failed(self):
        return [r for r in self.results if not r[1]]


class Env:
    def __init__(self, launcher, work):
        self.launcher = launcher
        self.work = work
        self.vm_dir = os.path.join(work, "vm")
        self.notes = os.path.join(work, "notes.txt")
        with open(self.notes, "w") as f:
            f.write("notes-via-fwcfg\n")
        self.lan = lan_ip()
        self.loopback_server = serve("127.0.0.1", LOOPBACK_SERVER_PORT)
        self.any_server = serve("0.0.0.0", ANY_SERVER_PORT)

    def base_args(self):
        return ["--dir", self.vm_dir, "--disk-size", "1", "--memory", "2048", "--cores", "2"]


def guest_network(scenario, guest):
    _, rc = guest.run("ip link set eth0 up; udhcpc -i eth0 -n -q -t 10 >/dev/null 2>&1")
    out, _ = guest.run("ip -4 addr show eth0")
    scenario.check("DHCP gives the guest its lease", rc == 0 and GUEST_IP in out, out)
    _, rc = guest.run("nslookup example.com >/dev/null 2>&1")
    scenario.check("DNS resolves through the gateway", rc == 0)
    _, rc = guest.run("wget -q -T 15 -O /dev/null https://dl-cdn.alpinelinux.org/alpine/MIRRORS.txt")
    scenario.check("HTTPS to the internet works", rc == 0)


def guest_isolation(scenario, guest, env):
    out, rc = guest.run(f"wget -q -T 5 -O - http://{GATEWAY_IP}/services/forwarder/all")
    scenario.check("the gateway serves no API to the guest", rc != 0, out)
    out, rc = guest.run(f"wget -q -T 5 -O - http://{HOST_VIRTUAL_IP}:{LOOPBACK_SERVER_PORT}/")
    scenario.check("no virtual IP maps to the host loopback", rc != 0 and SERVER_MARKER not in out, out)
    if env.lan:
        out, rc = guest.run(f"wget -q -T 5 -O - http://{env.lan}:{ANY_SERVER_PORT}/")
        scenario.check("the host's LAN address is unreachable", rc != 0 and SERVER_MARKER not in out, out)
    else:
        log("  skip the LAN probe: no route to the internet")


def guest_forward(scenario, guest, env):
    guest.run(
        "(while true; do printf 'HTTP/1.0 200 OK\\r\\n\\r\\nhello-from-guest\\n' | nc -l -p %d; done) >/dev/null 2>&1 &"
        % GUEST_PORT
    )
    time.sleep(1)
    out = http_get(f"http://127.0.0.1:{FORWARD_PORT}/")
    scenario.check("the forward answers on the host loopback", "hello-from-guest" in out, out)
    if env.lan:
        out = http_get(f"http://{env.lan}:{FORWARD_PORT}/", timeout=3)
        scenario.check("the forward is not on the LAN address", "hello-from-guest" not in out, out)
    sockets = listening_sockets("gvproxy")
    scenario.check(
        "gvproxy holds one TCP listener, on loopback",
        sockets == [f"127.0.0.1:{FORWARD_PORT}"],
        " ".join(sockets),
    )


def scenario_headless(env):
    s = Scenario("headless")
    denials = Denials()
    guest = Guest(
        env.launcher,
        env.base_args()
        + ["-p", f"{GUEST_PORT}:{FORWARD_PORT}", "--file", f"notes.txt={env.notes}", "--persistent"],
    )
    guest_network(s, guest)
    guest_isolation(s, guest, env)
    guest_forward(s, guest, env)
    out = monitor_command(guest.monitor, "info name")
    s.check("the monitor answers on its socket", "qemu-nixos" in out or "QEMU" in out, out)
    marker = os.path.join(env.work, "pwned-by-monitor")
    out = monitor_command(guest.monitor, f'migrate "exec:/usr/bin/touch {marker}"')
    s.check("the monitor cannot run host commands", "Failed to fork" in out and not os.path.exists(marker), out)
    out, rc = guest.run(
        "modprobe qemu_fw_cfg 2>/dev/null; cat /sys/firmware/qemu_fw_cfg/by_name/opt/qemu-vm/notes.txt/raw"
    )
    s.check("--file reaches the guest through fw_cfg", "notes-via-fwcfg" in out, out)
    _, rc = guest.run("mount /dev/vda /mnt && echo persist-marker > /mnt/marker && umount /mnt")
    s.check("the guest can write its disk", rc == 0)
    tail = guest.poweroff()
    s.check("the launcher exits 0 after poweroff", guest.exit_status == 0, tail[-300:])
    bad = unexpected(denials.stop())
    s.check("no unexpected sandbox denials", not bad, "\n    ".join(bad))
    return s


def scenario_disk(env):
    """An ephemeral boot sees the marker and its own write is discarded."""
    s = Scenario("disk")
    guest = Guest(env.launcher, env.base_args() + ["--ephemeral"])
    out, _ = guest.run("mount /dev/vda /mnt && cat /mnt/marker; echo ephemeral > /mnt/marker2; sync; umount /mnt")
    s.check("the ephemeral boot sees the persistent marker", "persist-marker" in out, out)
    guest.poweroff()
    guest = Guest(env.launcher, env.base_args() + ["--persistent"])
    out, _ = guest.run("mount /dev/vda /mnt && ls /mnt; umount /mnt")
    s.check("the ephemeral write was discarded", "marker2" not in out, out)
    guest.poweroff()
    return s


def scenario_gui(env):
    s = Scenario("gui")
    denials = Denials()
    guest = Guest(env.launcher, env.base_args() + ["--ephemeral", "--gui", "--clipboard"])
    guest_network(s, guest)
    windows = qemu_windows()
    s.check("a QEMU window is on screen", windows, "none found")
    out, _ = guest.run("cat /proc/bus/input/devices | grep -c Name")
    s.check("the guest sees the keyboard and tablet", out.strip() not in ("", "0"), out)
    out, _ = guest.run("ls /dev/virtio-ports/")
    s.check("the guest sees the clipboard port", "com.redhat.spice.0" in out, out)
    tail = guest.poweroff()
    s.check("Cocoa printed no errors", "Connection invalid" not in tail and "Abort trap" not in tail, tail[-300:])
    bad = unexpected(denials.stop())
    s.check("no unexpected sandbox denials", not bad, "\n    ".join(bad))
    return s


def scenario_no_network(env):
    s = Scenario("no-network")
    denials = Denials()
    guest = Guest(env.launcher, env.base_args() + ["--ephemeral", "--no-network"])
    out, _ = guest.run("ls /sys/class/net")
    s.check("the guest has no NIC", out.split() == ["lo"], out)
    s.check("no gvproxy process runs", subprocess.run(["pgrep", "-x", "gvproxy"], capture_output=True).returncode != 0)
    guest.poweroff()
    bad = unexpected(denials.stop())
    s.check("no unexpected sandbox denials", not bad, "\n    ".join(bad))
    return s


def scenario_no_sandbox(env):
    """Without Seatbelt, gvproxy's own guard keeps the host out of reach."""
    s = Scenario("no-sandbox")
    guest = Guest(
        env.launcher,
        env.base_args() + ["--ephemeral", "--no-sandbox", "-p", f"{GUEST_PORT}:{FORWARD_PORT}"],
    )
    guest_network(s, guest)
    guest_isolation(s, guest, env)
    guest_forward(s, guest, env)
    guest.poweroff()
    return s


SCENARIOS = {
    "headless": scenario_headless,
    "disk": scenario_disk,
    "gui": scenario_gui,
    "no-network": scenario_no_network,
    "no-sandbox": scenario_no_sandbox,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--launcher", required=True, help="the qemu-vm launcher to drive")
    parser.add_argument(
        "--only",
        default=",".join(SCENARIOS),
        help="comma-separated scenarios to run (default: all, in this order: %(default)s)",
    )
    args = parser.parse_args()
    wanted = [n.strip() for n in args.only.split(",") if n.strip()]
    unknown = [n for n in wanted if n not in SCENARIOS]
    if unknown:
        parser.error(f"unknown scenario: {', '.join(unknown)}")
    if sys.platform != "darwin":
        parser.error("the sandbox check runs on macOS only")

    work = tempfile.mkdtemp(prefix="qemu-vm-sandbox-check.")
    env = Env(args.launcher, work)
    failures = []
    try:
        for name in wanted:
            log(f"== {name}")
            try:
                scenario = SCENARIOS[name](env)
            except Failure as e:
                log(f"  FAIL {e}")
                failures.append((name, str(e)))
                continue
            failures.extend((name, r[0]) for r in scenario.failed)
    finally:
        shutil.rmtree(work, ignore_errors=True)
        subprocess.run(["pkill", "-x", "gvproxy"], capture_output=True)

    if failures:
        log("\nFAILED:")
        for name, what in failures:
            log(f"  {name}: {what}")
        sys.exit(1)
    log("\nall scenarios passed")


if __name__ == "__main__":
    main()
