"""Store model IDs as hexadecimal filenames to preserve case on every filesystem."""

from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

MODEL = re.compile(r"^(models|providers/[^/]+/models)/(.+)\.toml$")


def unpack(source, destination):
    destination = Path(destination)
    destination.mkdir()
    names = {}
    with tarfile.open(source) as archive:
        for member in archive:
            parts = PurePosixPath(member.name).parts
            if len(parts) < 2:
                continue
            name = "/".join(parts[1:])
            match = MODEL.fullmatch(name)
            if match and not member.isdir():
                prefix, model_id = match.groups()
                target = destination / prefix / (model_id.encode().hex() + ".toml")
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as stream:
                    target.write_bytes(stream.read())
                continue
            # Model subdirectories are replaced by the encoded filenames.
            if member.isdir() and re.match(r"^(models|providers/[^/]+/models)/", name):
                continue
            folded = name.casefold()
            if folded in names and names[folded] != name:
                raise ValueError(f"Source paths differ only by case: {names[folded]} and {name}")
            names[folded] = name
            member.name = name
            archive.extract(member, destination, filter="data")


if __name__ == "__main__":
    unpack(*sys.argv[1:])
