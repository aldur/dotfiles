import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time


wrapper = sys.argv[1]
machine_id = "0123456789abcdef0123456789abcdef"
boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip().replace("-", "")
roots = [Path("/var/log/journal"), Path("/run/log/journal")]
assert not any(root.exists() for root in roots)
assert not Path("/etc/machine-id").exists()
subprocess.run([wrapper, "--journal", "--", "true"], check=True, timeout=20)
Path("/etc/machine-id").write_text(machine_id + "\n")

with socket.socket(socket.AF_UNIX) as journal_socket:
    Path("/run/systemd/journal").mkdir(parents=True)
    journal_socket.bind("/run/systemd/journal/socket")
    for root in roots:
        directory = root / machine_id
        directory.mkdir(parents=True)
        files = []
        for name, fields, message in [
            ("system.journal", "_SYSTEMD_UNIT=fixture.service", "system fixture"),
            (f"user-{os.getuid()}.journal", f"_SYSTEMD_USER_UNIT=fixture.service\n_UID={os.getuid()}", "user fixture"),
        ]:
            path = directory / name
            entry = (f"__REALTIME_TIMESTAMP={time.time_ns() // 1000}\n"
                     f"__MONOTONIC_TIMESTAMP=1\n_BOOT_ID={boot_id}\n"
                     f"_MACHINE_ID={machine_id}\n{fields}\nMESSAGE={message}\n\n")
            subprocess.run([
                "@journalRemote@", "--split-mode=none", f"--output={path}", "-",
            ], input=entry, text=True, capture_output=True, check=True, timeout=20)
            files.append(str(path))

        subprocess.run([
            wrapper, "--", sys.executable, "-c",
            "from pathlib import Path; "
            "assert not Path('/etc/machine-id').exists(); "
            "assert not Path('/var/log/journal').exists(); "
            "assert not Path('/run/log/journal').exists()",
        ], check=True, timeout=20)
        for options in (["--journal"], ["--profile", "journal"]):
            for scope, message in [("--system", "system fixture"), ("--user", "user fixture")]:
                result = subprocess.run([
                    wrapper, *options, "--", "@journalctl@", scope, "--unit=fixture.service",
                    "--boot=0", "--no-pager", "--output=cat",
                ], capture_output=True, text=True, check=True, timeout=20)
                assert result.stdout.strip() == message, result
            subprocess.run([
                wrapper, *options, "--", sys.executable, "-c", """
import errno
from pathlib import Path
import sys
assert not Path('/run/systemd/journal/socket').exists()
assert not Path('/run/dbus/system_bus_socket').exists()
assert not Path('/var/lib/unrelated/secret').exists()
assert not Path('/etc/unrelated-secret').exists()
for name in ['/etc/machine-id', *sys.argv[1:]]:
    try:
        with open(name, 'r+'):
            pass
    except OSError as error:
        assert error.errno == errno.EROFS, error
    else:
        raise AssertionError(f'journal grant is writable: {name}')
""", *files,
            ], check=True, timeout=20)
        shutil.rmtree(root)

Path("/etc/machine-id").unlink()
print("passed: opt-in read-only system and user journals in persistent and runtime storage", flush=True)
