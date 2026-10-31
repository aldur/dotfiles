"""Test the age plugin boundary without a YubiKey. Use software age keys."""

import base64
import os
from pathlib import Path
import subprocess
import sys
import textwrap

KEYS = {
    "first": ("age1yubikey1qq0w0756", "AGE-PLUGIN-YUBIKEY-1QQQVUTDQ"),
    "second": ("age1yubikey1pqqnqylu", "AGE-PLUGIN-YUBIKEY-1PQ03N3XX"),
    "unknown": ("age1yubikey1zq3a3rzk", "AGE-PLUGIN-YUBIKEY-1ZQ7LZKMV"),
    "fallback": ("age1test1qq2y9hht", "AGE-PLUGIN-TEST-1QQK45Y5S"),
}


def receive():
    header = sys.stdin.readline()
    if not header.startswith("-> "):
        raise ValueError(f"Invalid plugin command: {header!r}")
    body = ""
    while True:
        line = sys.stdin.readline().rstrip("\n")
        body += line
        if len(line) < 64:
            break
    return header[3:].split(), base64.b64decode(body + "=" * (-len(body) % 4))


def send(args, body=b"", acknowledge=True):
    encoded = base64.b64encode(body).decode().rstrip("=")
    lines = textwrap.wrap(encoded, 64)
    if len(encoded) % 64 == 0:
        lines.append("")
    print("-> " + " ".join(args))
    print("\n".join(lines), flush=True)
    if acknowledge:
        response, _ = receive()
        assert response == ["ok"], response


if sys.argv[1:] == ["--identity"]:
    for name in os.environ.get("CONNECTED", "").split(","):
        if name in KEYS:
            print(f"# {name}\n  {KEYS[name][1]}  \n")
    sys.exit(int(os.environ.get("DISCOVERY_STATUS", "0")))

mode = sys.argv[1]
commands = []
while True:
    args, body = receive()
    if args[0] == "done":
        break
    commands.append((args, body))

# Each recipient uses a separate software key. Both keys are needed to test
# that encryption retains both recipients.
if mode == "--age-plugin=recipient-v1":
    recipients = [args[1] for args, _ in commands if args[0] == "add-recipient"]
    file_keys = [body for args, body in commands if args[0] == "wrap-file-key"]
    for index, file_key in enumerate(file_keys):
        for name, (recipient, _) in KEYS.items():
            if recipient not in recipients:
                continue
            key = Path(os.environ["TEST_KEYS"]) / name
            public = subprocess.check_output(["age-keygen", "-y", str(key)]).strip()
            wrapped = subprocess.check_output(["age", "-r", public], input=file_key)
            send(["recipient-stanza", str(index), "test-yubikey", name], wrapped)
elif mode == "--age-plugin=identity-v1":
    identities = [args[1] for args, _ in commands if args[0] == "add-identity"]
    connected = os.environ.get("CONNECTED", "").split(",")
    available = [KEYS[name][1] for name in connected if name in KEYS]
    available.append(KEYS["fallback"][1])
    assert identities and all(identity in available for identity in identities), (
        identities
    )
    returned = set()
    for args, payload in commands:
        if args[0] != "recipient-stanza" or args[2] != "test-yubikey":
            continue
        index, name = args[1], args[3]
        if index in returned or KEYS[name][1] not in identities:
            continue
        key = Path(os.environ["TEST_KEYS"]) / name
        file_key = subprocess.check_output(["age", "-d", "-i", str(key)], input=payload)
        send(["file-key", index], file_key)
        returned.add(index)
else:
    raise ValueError(mode)
send(["done"], acknowledge=False)
