"""Change a task through the UI with no taskmd on the caller's PATH."""

import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import termios
import time

import yaml


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    tasks = root / "tasks"
    tasks.mkdir()
    task = tasks / "001-fixture.md"
    task.write_text('---\nid: "001"\ntitle: Packaging fixture\nstatus: pending\n---\n\nKeep this body.\n')
    master, slave = pty.openpty()
    termios.tcsetwinsize(slave, (40, 120))
    process = subprocess.Popen(
        [sys.argv[1], "-d", str(tasks)], cwd=root,
        env=os.environ | {"HOME": str(root), "PATH": "", "TERM": "xterm-256color"},
        stdin=slave, stdout=slave, stderr=slave,
    )
    os.close(slave)
    output = bytearray()

    def wait_for(condition):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            # Read the state one time. The process can exit between two reads.
            exited = process.poll() is not None
            if condition():
                return
            assert not exited, output.decode(errors="replace")
        raise AssertionError(output.decode(errors="replace"))

    def status():
        # taskmd truncates the file before it writes the new text.
        # A read in that gap gets no complete frontmatter.
        parts = task.read_text().split("---", 2)
        return yaml.safe_load(parts[1])["status"] if len(parts) == 3 else None

    try:
        wait_for(lambda: b"Packaging fixture" in output)
        os.write(master, b"2")
        wait_for(lambda: status() == "in-progress")
        assert "Keep this body." in task.read_text()
        os.write(master, b"q")
        wait_for(lambda: process.poll() is not None)
        assert process.returncode == 0, output.decode(errors="replace")
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
