"""Regression injections for the image guard, without rebuilding a whole image."""
import importlib.util
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tarfile
import unittest

script = Path(sys.argv.pop(1))
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("image_guard", script)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ImageGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.nodes = []
        self.nix = self.package("nix-2.35.2")
        self.root = self.package("nixos-system-fixture", refs=[self.nix])
        self.config = {"store_layers": [[self.root, self.nix]], "from_image": None}
        self.policy = {"maxClosureMiB": 1, "maxArchiveMiB": 1, "forbiddenPaths": []}

    def package(self, name, refs=(), size=100, files=()):
        path = self.directory / f"{len(self.nodes):032d}-{name}"
        path.mkdir()
        for file in files:
            target = path / file
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()
        self.nodes.append({"path": str(path), "narSize": size, "references": list(refs)})
        return str(path)

    def inject(self, package):
        helper = self.package("new-helper", refs=[package])
        next(n for n in self.nodes if n["path"] == self.root)["references"].append(helper)
        self.config["store_layers"].append([helper, package])
        return helper

    def metadata(self):
        return {"image": self.nodes, "nixRuntime": [{"path": self.nix}]}

    def check(self):
        return guard.check_closure(self.config, self.metadata(), self.policy)

    def test_only_shipped_paths_count_and_shared_paths_count_once(self):
        build_tool = self.package("build-only", size=100 * guard.MIB)
        self.policy["forbiddenPaths"] = [build_tool]
        self.config["store_layers"].append([self.nix])
        report, errors = self.check()
        self.assertEqual(errors, [])
        self.assertEqual(report["closureBytes"], 200)

    def test_git_returning_through_a_new_helper_exits_nonzero_with_chain(self):
        git = self.package("git-9.99.0", files=["bin/git"])
        helper = self.inject(git)
        result = self.cli("closure")
        self.assertEqual(result.returncode, 1)
        self.assertIn("full Git runtime returned", result.stderr)
        self.assertIn(f"{self.root} -> {helper} -> {git}", result.stderr)

    def test_git_docs_remain_allowed(self):
        self.inject(self.package("git-9.99.0-doc", files=["share/doc/git/index.html"]))
        self.assertEqual(self.check()[1], [])

    def test_another_nix_build_is_rejected_even_at_the_same_version(self):
        for name in ("nix-2.34.8", "nix-expr-2.34.8", "nix-2.35.2"):
            with self.subTest(name=name):
                path = self.package(name)
                self.inject(path)
                self.assertTrue(any(path in e and "selected nix.package" in e for e in self.check()[1]))

    def test_nix_man_pages_are_not_a_second_runtime(self):
        self.inject(self.package("nix-2.35.2-man", files=["share/man/man1/nix.1.gz"]))
        self.assertEqual(self.check()[1], [])

    def test_new_nix_library_names_are_still_checked(self):
        path = self.package("nix-new-component", files=["lib/libnixnew.so"])
        self.inject(path)
        self.assertTrue(any(path in e and "selected nix.package" in e for e in self.check()[1]))

    def test_original_library_is_rejected_even_without_archives(self):
        path = self.package("libvpx-1.16.0", files=["lib/libvpx.so"])
        self.policy["forbiddenPaths"] = [path]
        self.inject(path)
        self.assertTrue(any("original, untrimmed" in e for e in self.check()[1]))

    def test_static_archives_in_another_library_build_are_rejected(self):
        for name in ("libvpx-9.0", "libimagequant-9.0", "qpdf-99.0-lib"):
            with self.subTest(name=name):
                path = self.package(name, files=["lib/returned.a"])
                self.inject(path)
                self.assertTrue(any(path in e and "static archives returned" in e for e in self.check()[1]))

    def test_duplicate_trimmed_libraries_are_rejected(self):
        for _ in range(2):
            self.inject(self.package("libvpx-1.16.0", files=["lib/libvpx.so"]))
        self.assertTrue(any("duplicate libvpx runtime" in e for e in self.check()[1]))

    def test_closure_budget_exits_nonzero_with_largest_contributors(self):
        self.inject(self.package("unexpected-large-package", size=2 * guard.MIB))
        result = self.cli("closure")
        self.assertEqual(result.returncode, 1)
        self.assertIn("unpacked closure exceeds", result.stderr)
        self.assertIn("Largest shipped store paths", result.stderr)
        self.assertIn("unexpected-large-package", result.stderr)

    def test_compressed_budget_uses_actual_archive_bytes(self):
        self.assertEqual(self.cli("closure").returncode, 0)
        archive = self.directory / "image.tar"
        archive.write_bytes(b"x" * guard.MIB)
        self.assertEqual(self.cli("archive", archive).returncode, 0)
        with archive.open("ab") as file:
            file.write(b"x")
        result = self.cli("archive", archive)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Compressed OCI archive exceeds", result.stderr)
        self.assertIn("retained by:", result.stderr)

    def test_incomplete_layer_metadata_fails_closed(self):
        self.config["store_layers"].append(["/nix/store/missing"])
        with self.assertRaisesRegex(ValueError, "missing from reference graph"):
            self.check()

    def test_actual_oci_layers_supply_the_file_inventory(self):
        import zstandard
        package = "/nix/store/" + "a" * 32 + "-libvpx-99.0"
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode="w") as layer:
            entry = tarfile.TarInfo(package.lstrip("/") + "/lib/returned.a")
            entry.size = 1
            layer.addfile(entry, io.BytesIO(b"x"))
            layer.addfile(tarfile.TarInfo("nix/store/.links"))
        for compression, encode in (
            ("+gzip", gzip.compress),
            ("+zstd", zstandard.ZstdCompressor().compress),
            ("", lambda data: data),
        ):
            with self.subTest(compression=compression):
                blobs = {}
                def blob(data):
                    digest = hashlib.sha256(data).hexdigest()
                    blobs["blobs/sha256/" + digest] = data
                    return {"digest": "sha256:" + digest, "size": len(data)}
                descriptor = blob(encode(raw.getvalue()))
                descriptor["mediaType"] = "application/vnd.oci.image.layer.v1.tar" + compression
                manifest = blob(json.dumps({"layers": [descriptor]}).encode())
                blobs["index.json"] = json.dumps({"manifests": [manifest]}).encode()
                archive = self.directory / "fixture.tar"
                with tarfile.open(archive, "w") as output:
                    for name, data in blobs.items():
                        entry = tarfile.TarInfo("./" + name)
                        entry.size = len(data)
                        output.addfile(entry, io.BytesIO(data))
                inventory = guard.image_contents(archive)
                metadata = {"image": [{"path": package, "references": [], "narSize": 1}], "nixRuntime": []}
                _, errors = guard.check_closure(inventory, metadata, self.policy)
                self.assertTrue(any("static archives returned: lib/returned.a" in e for e in errors))

    def test_empty_and_inherited_images_fail_closed(self):
        self.config["store_layers"] = []
        with self.assertRaisesRegex(ValueError, "no store paths"):
            self.check()
        self.config["from_image"] = "/an/uninspected/base/image"
        with self.assertRaisesRegex(ValueError, "without fromImage"):
            self.check()

    def cli(self, mode, *extra):
        for name, content in (("policy", self.policy), ("config", self.config), ("graph", self.metadata())):
            (self.directory / f"{name}.json").write_text(json.dumps(content))
        command = [sys.executable, str(script), mode, "--policy", str(self.directory / "policy.json"),
                   "--report", str(self.directory / "report.json")]
        if mode == "closure":
            command += ["--config", str(self.directory / "config.json"), "--graph", str(self.directory / "graph.json")]
        return subprocess.run(command + list(map(str, extra)), capture_output=True, text=True, timeout=10)


unittest.main()
