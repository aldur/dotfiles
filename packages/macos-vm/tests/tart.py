"""Minimal Tart double: record calls and model persistent VM creation."""

import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
with open(os.environ["VM_TEST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")

if args[0] == os.environ.get("VM_TEST_FAIL"):
    sys.exit(42)

root = Path(os.environ["TART_HOME"]) / "vms"
if args[0] in ("create", "clone"):
    name = args[1] if args[0] == "create" else args[2]
    (root / name).mkdir(parents=True)
elif args[0] in ("run", "set", "ip", "stop"):
    if not (root / args[1]).is_dir():
        sys.exit(1)
    if args[0] == "ip":
        print("192.0.2.10")
else:
    raise AssertionError(args)
