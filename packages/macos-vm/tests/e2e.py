"""Real macOS boot, unattended provisioning, activation and persistence test.

Leaves the stopped guest and logs in --dir for inspection; never deletes a VM.
"""
import argparse
from pathlib import Path
import subprocess
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("--launcher", required=True)
parser.add_argument("--dir", required=True)
parser.add_argument("--image", help="Optional local/OCI image to clone")
parser.add_argument("--name", default="e2e-" + uuid.uuid4().hex[:10])
args = parser.parse_args()
state = Path(args.dir).resolve()
state.mkdir(parents=True, exist_ok=True)
assert not (state / "vms" / args.name).exists(), "E2E requires a new VM name"
base = [args.launcher, "--dir", str(state), "--name", args.name]
ssh_config = state / (".macos-vm-" + args.name) / "ssh_config"
process = None


def ssh(script):
    return subprocess.run(
        ["/usr/bin/ssh", "-F", str(ssh_config), "-o", "BatchMode=yes", "guest", "/bin/bash -s"],
        input=script, text=True, check=True, capture_output=True, timeout=600,
    ).stdout


def boot(number):
    global process
    log = state / f"{args.name}-boot-{number}.log"
    command = base + (["--image", args.image] if number == 1 and args.image else [])
    with log.open("w") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 7200
    next_update = time.monotonic()
    while time.monotonic() < deadline:
        content = log.read_text(errors="replace")
        if "Ready: macos-vm" in content:
            subprocess.run(base + ["--check"], check=True, timeout=120)
            return content
        if process.poll() is not None:
            raise RuntimeError(f"Boot {number} exited {process.returncode}:\n{content[-12000:]}")
        if time.monotonic() >= next_update:
            print(f"Boot {number}: waiting; log: {log}", flush=True)
            next_update = time.monotonic() + 30
        time.sleep(2)
    raise TimeoutError(f"Boot timed out; inspect {log}")


try:
    first = boot(1)
    assert "Provisioning Nix" in first
    print(ssh("set -eu\nsw_vers\nreadlink /run/current-system\nprintf 'persistent\n' > /Users/admin/macos-vm-e2e-marker\n"), flush=True)
    print(ssh("set -eu\nexport PATH=/run/current-system/sw/bin:/etc/profiles/per-user/admin/bin:/usr/bin:/bin:/usr/sbin:/sbin\nnvim --headless +qa\ncodex --version\nclaude --version\n"), flush=True)
    # Reapplying the same configuration must work without intervention too.
    print(ssh("set -eu\nsudo -n /run/current-system/activate\n"), flush=True)
    subprocess.run(base + ["--check"], check=True, timeout=120)
    # A clean shutdown and cold boot verify that configuration survives restart.
    try:
        ssh("sudo -n /sbin/shutdown -h now\n")
    except subprocess.CalledProcessError as exc:
        if exc.returncode != 255:
            raise
    process.wait(timeout=180)
    assert process.returncode == 0
    second = boot(2)
    assert "Provisioning Nix" not in second, "unchanged system was needlessly reprovisioned"
    assert ssh("cat /Users/admin/macos-vm-e2e-marker\n").strip() == "persistent"
    print("PASS: unattended first boot, nix-darwin + Home Manager, application startup, repeated activation, cold reboot and persistent data", flush=True)
finally:
    if process is not None and process.poll() is None:
        subprocess.run(base + ["--stop"], timeout=60, check=False)
        process.wait(timeout=60)
    print(f"Stopped test VM retained: {args.name}; state and logs: {state}", flush=True)
