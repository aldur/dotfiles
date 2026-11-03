import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile


wrapper = sys.argv[1]
contents = {
    "passwd": Path("/etc/passwd").read_bytes(),
    "group": f"tester:x:{os.getgid()}:\n".encode(),
}
snapshots = set(Path("/tmp").glob("agent-sandbox-accounts-*"))
with tempfile.TemporaryDirectory(prefix="account-fixture-") as temporary:
    directory = Path(temporary)
    for name, data in contents.items():
        (directory / name).write_bytes(data)
    check = """
import errno
from pathlib import Path
for name, data in CONTENTS.items():
    path = Path('/etc') / name
    assert path.read_bytes() == data, path
    assert path.stat().st_nlink > 0, path
    try:
        path.open('r+b').close()
    except OSError as error:
        assert error.errno == errno.EROFS, error
    else:
        raise AssertionError(f'account file is writable: {path}')
""".replace("CONTENTS", repr(contents))
    script = f"""
import subprocess
import sys
print('ready', flush=True)
assert sys.stdin.readline() == 'continue\\n'
exec({check!r})
subprocess.run([
    '@bwrap@', '--ro-bind', '/', '/',
    '--ro-bind', '/etc/passwd', '/etc/passwd',
    '--ro-bind', '/etc/group', '/etc/group',
    '--', sys.executable, '-c', {check!r},
], check=True, timeout=20)
"""
    process = subprocess.Popen([
        "@bwrap@", "--dev-bind", "/", "/", "--bind", str(directory), "/etc",
        "--", wrapper, "--", sys.executable, "-c", script,
    ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert select.select([process.stdout], [], [], 20)[0], "sandbox did not start"
        ready = process.stdout.readline()
        assert ready == "ready\n", (ready, process.communicate(timeout=5))
        # Replace the host files while the sandbox is running, as activation does.
        for name, data in contents.items():
            replacement = directory / (name + ".new")
            replacement.write_bytes(data + b"# replacement\n")
            replacement.replace(directory / name)
        stdout, stderr = process.communicate("continue\n", timeout=30)
        assert process.returncode == 0, (stdout, stderr)
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=5)
assert set(Path("/tmp").glob("agent-sandbox-accounts-*")) == snapshots
print("passed: read-only account snapshots survive host replacement and nested mounts", flush=True)
