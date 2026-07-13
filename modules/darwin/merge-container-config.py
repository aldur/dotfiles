# Idempotently set `machine.homeMount = "none"` in Apple `container`'s config,
# preserving every other key, comment, and formatting already in the file.
# See modules/darwin/home.nix for why this runs at activation time instead of
# being a `home.file` entry. Tested by tests/merge-container-config-test.nix.
import sys

import tomlkit

path = sys.argv[1]
try:
    with open(path) as f:
        doc = tomlkit.parse(f.read())
except FileNotFoundError:
    doc = tomlkit.document()

doc.setdefault("machine", tomlkit.table())["homeMount"] = "none"

with open(path, "w") as f:
    f.write(tomlkit.dumps(doc))
