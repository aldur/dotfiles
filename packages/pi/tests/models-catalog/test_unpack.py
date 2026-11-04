import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from unpack import unpack


class UnpackTest(unittest.TestCase):
    def test_other_case_collisions_fail_with_both_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.tar"
            with tarfile.open(source, "w") as archive:
                for name in ("Readme", "README"):
                    archive.addfile(tarfile.TarInfo(f"source/{name}"), io.BytesIO())
            with self.assertRaisesRegex(ValueError, "Readme and README"):
                unpack(source, root / "unpacked")

    def test_model_ids_keep_case_and_symlink_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.tar"
            models = {
                "Qwen/Model": b"upper",
                "qwen/model": b"lower",
                "qwen/Model": b"mixed",
            }
            with tarfile.open(source, "w") as archive:
                for model_id, content in models.items():
                    member = tarfile.TarInfo(f"source/providers/example/models/{model_id}.toml")
                    member.size = len(content)
                    archive.addfile(member, io.BytesIO(content))
                alias = tarfile.TarInfo("source/providers/example/models/alias.toml")
                alias.type = tarfile.SYMTYPE
                alias.linkname = "Qwen/Model.toml"
                archive.addfile(alias)
            unpack(source, root / "unpacked")
            files = list((root / "unpacked/providers/example/models").iterdir())
            self.assertEqual(len({p.name.casefold() for p in files}), 4)
            self.assertEqual(
                {bytes.fromhex(p.stem).decode(): p.read_bytes() for p in files},
                models | {"alias": b"upper"},
            )


if __name__ == "__main__":
    unittest.main()
