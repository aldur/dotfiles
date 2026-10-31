"""Print a GitHub access token. Keep credentials in an age-encrypted file."""

import argparse
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

import requests

# Public GitHub CLI credentials: https://github.com/cli/cli/blob/trunk/internal/authflow/flow.go
CLIENT_ID = "178c6fc778ccc68e1d6a"
CLIENT_SECRET = "34ddeff2b558a23d38fba8a6de74f086ede1cc0b"
ENDPOINT = "https://github.com/login/oauth/access_token"


class TokenError(Exception):
    pass


def valid_token(value):
    return isinstance(value, str) and bool(value) and not any(c.isspace() for c in value)


def exchange(refresh):
    try:
        response = requests.post(
            ENDPOINT,
            data={
                "grant_type": "refresh_token",
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "refresh_token": refresh,
            },
            headers={"Accept": "application/json"},
            timeout=30,
            allow_redirects=False,
        )
    except requests.RequestException:
        raise TokenError("GitHub request failed; no automatic retry was made") from None
    if response.status_code != 200:
        raise TokenError(f"GitHub returned HTTP {response.status_code}")
    try:
        result = response.json()
    except ValueError:
        raise TokenError("GitHub returned invalid JSON") from None
    if not isinstance(result, dict):
        raise TokenError("GitHub returned an invalid token response")
    if "error" in result:
        code = result["error"]
        suffix = f" ({code})" if isinstance(code, str) and re.fullmatch(r"[a-z_]{1,64}", code) else ""
        raise TokenError(f"GitHub rejected the refresh request{suffix}")
    if not all(valid_token(result.get(key)) for key in ("access_token", "refresh_token")):
        raise TokenError("GitHub did not return both tokens")
    if type(result.get("expires_in")) is not int or result["expires_in"] <= 0:
        raise TokenError("GitHub did not return a valid access token lifetime")
    return result


def age(args, data=None):
    try:
        return subprocess.run(
            [os.environ.get("GH_TOKEN_AGE", "age"), *args],
            input=data,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
    except subprocess.CalledProcessError:
        raise TokenError("age failed; credentials were not updated") from None


def setting(name):
    value = os.environ.get(name)
    if not value:
        raise TokenError(f"set {name} to the configured age file")
    return value


def save(path, credentials):
    ciphertext = age(
        ["-e", "-R", setting("GH_TOKEN_RECIPIENTS_FILE")],
        json.dumps(credentials).encode(),
    )
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        output.write(ciphertext)
        output.flush()
        os.fsync(output.fileno())
    try:
        os.replace(output.name, path)
    except OSError:
        raise TokenError(f"could not replace credentials; recover the encrypted replacement from {output.name}") from None
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def access_token(path):
    if not path.exists():
        raise TokenError("run 'gh-token init' to import a refresh token")
    plaintext = age(["-d", "-i", setting("GH_TOKEN_IDENTITIES_FILE"), str(path)])
    try:
        credentials = json.loads(plaintext)
    except (ValueError, UnicodeError):
        raise TokenError("the encrypted credentials contain invalid JSON") from None
    if not isinstance(credentials, dict) or not valid_token(credentials.get("refresh_token")):
        raise TokenError("the encrypted credentials do not contain a refresh token")
    if "access_token" in credentials:
        expiry = credentials.get("expires_at")
        if (
            not valid_token(credentials["access_token"])
            or type(expiry) not in (int, float)
            or not 0 < expiry < float("inf")
        ):
            raise TokenError("the encrypted credentials contain an invalid access token or expiry")
        if time.time() + 60 < expiry:
            return credentials["access_token"]

    # Check encryption before GitHub invalidates the refresh token.
    age(["-e", "-R", setting("GH_TOKEN_RECIPIENTS_FILE")], b"")
    # Measure from before the request to avoid extending the token lifetime.
    requested_at = time.time()
    credentials = exchange(credentials["refresh_token"])
    credentials["expires_at"] = requested_at + credentials["expires_in"]
    save(path, credentials)
    return credentials["access_token"]


def main():
    parser = argparse.ArgumentParser(prog="gh-token", description=__doc__)
    parser.add_argument("action", nargs="?", choices=["init"], help="import a refresh token from stdin or a hidden prompt")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        directory = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "gh-token"
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        path = directory / "credentials.age"
        with (directory / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.action == "init":
                if path.exists():
                    raise TokenError(f"credentials already exist; remove {path} before a new import")
                refresh = getpass.getpass("GitHub refresh token: ") if sys.stdin.isatty() else sys.stdin.readline().strip()
                if not valid_token(refresh):
                    raise TokenError("provide one refresh token on stdin or at the prompt")
                save(path, {"refresh_token": refresh})
            else:
                print(access_token(path))
    except (TokenError, OSError, EOFError) as error:
        print(f"gh-token: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
