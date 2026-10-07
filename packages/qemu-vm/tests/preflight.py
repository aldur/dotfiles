"""Regression checks for file errors that used to exit silently on macOS."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def check_launcher(launcher):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        files = root / "with spaces"
        files.mkdir()
        certificate = files / "certificate=example.p12"
        certificate.write_text("test fixture")
        link = root / "certificate-link.p12"
        link.symlink_to(certificate)
        broken_link = root / "broken.p12"
        broken_link.symlink_to(root / "missing.p12")
        unreadable = root / "unreadable.p12"
        unreadable.write_text("test fixture")
        unreadable.chmod(0)

        state = root / "state"
        state.mkdir()
        disk = state / "nixos.qcow2"
        disk.write_text("existing disk must survive invalid --file with --clean")
        original_disk = disk.read_bytes()
        store = root / "store.img"
        store.touch()

        def run(file_args, store_image=store, vm_dir=state):
            return subprocess.run(
                [
                    launcher,
                    "--no-network",
                    "--clean",
                    "--disk-size", "0",
                    "--dir", str(vm_dir),
                    "--store-image", str(store_image),
                    *file_args,
                ],
                cwd=root,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )

        invalid = [
            (["--file", "certificate.p12"], "Invalid file specification:"),
            (["--file", "../cert=example.p12"], "Invalid file specification:"),
            (["--file", "cert.p12="], "Invalid file specification:"),
            (["--file", ""], "Invalid file specification:"),
            (["--file", "cert.p12=/no/such/certificate.p12"], "Cannot read file:"),
            (["--file", "cert.p12=~/Downloads/Certificates.p12"], "shell left ~ unexpanded"),
            (["--file", f"cert.p12={files}"], "Cannot read file:"),
            (["--file", f"cert.p12={broken_link}"], "Cannot read file:"),
            (["--file", f"cert.p12={certificate}", "--file", "cert.password=missing"], "Cannot read file:"),
        ]
        if not os.access(unreadable, os.R_OK):
            invalid.append((["--file", f"cert.p12={unreadable}"], "Cannot read file:"))

        for args, message in invalid:
            for vm_dir in (state, root / "uncreated-state"):
                result = run(args, vm_dir=vm_dir)
                assert result.returncode == 1, (args, result)
                assert message in result.stderr, (args, result)
                assert "Creating VM disk:" not in result.stdout, result
                assert disk.read_bytes() == original_disk
                assert not (root / "uncreated-state").exists()

        # Successful preflight must preserve ordinary shell argument handling.
        # A bad store-image path stops the run before any disk/host operations,
        # and also exercises reporting for an otherwise silent readlink error.
        valid = [
            [],
            ["--file", f"cert.p12={certificate}"],
            ["--file", f"cert.p12={link}"],
            ["--file", "cert.p12=with spaces/certificate=example.p12"],
            ["--file", f"cert.p12={certificate}", "--file", f"cert.password={link}"],
        ]
        for args in valid:
            result = run(args, store_image=root / "missing-parent" / "store.img")
            assert result.returncode != 0, (args, result)
            assert "VM launcher failed at line" in result.stderr, (args, result)
            assert "Cannot read file:" not in result.stderr, (args, result)
            assert "Invalid file specification:" not in result.stderr, (args, result)
            assert disk.read_bytes() == original_disk

        unreadable.chmod(0o600)
        print(f"{Path(launcher).name}: file preflight and error reporting passed")


for command in sys.argv[1:]:
    check_launcher(command)
