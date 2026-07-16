import os
import stat
import sys
import tempfile
from collections.abc import MutableMapping
from pathlib import Path

import tomlkit


def merge(existing: MutableMapping, managed: MutableMapping) -> None:
    for key, value in managed.items():
        current = existing.get(key)
        if isinstance(current, MutableMapping) and isinstance(value, MutableMapping):
            merge(current, value)
        else:
            existing[key] = value


managed_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])

managed = tomlkit.loads(managed_path.read_text())
if target_path.exists():
    existing = tomlkit.loads(target_path.read_text())
    merge(existing, managed)
else:
    existing = managed

fd, temporary_name = tempfile.mkstemp(dir=target_path.parent, prefix=".config.toml.")
try:
    with os.fdopen(fd, "w") as temporary:
        temporary.write(tomlkit.dumps(existing))
    os.chmod(temporary_name, stat.S_IRUSR | stat.S_IWUSR)
    os.replace(temporary_name, target_path)
finally:
    if os.path.exists(temporary_name):
        os.unlink(temporary_name)
