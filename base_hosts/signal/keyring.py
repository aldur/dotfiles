"""Unlock/create the appliance keyring without passwords in argv or the store."""
import os
from pathlib import Path
import subprocess
import sys
import time

import dbus


def collection(bus):
    service = dbus.Interface(
        bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets"),
        "org.freedesktop.Secret.Service",
    )
    path = service.ReadAlias("default")
    if path == "/":
        return None
    return dbus.Interface(
        bus.get_object("org.freedesktop.secrets", path),
        "org.freedesktop.DBus.Properties",
    )


def ready(bus):
    store = collection(bus)
    return store is not None and not store.Get("org.freedesktop.Secret.Collection", "Locked")


def prompt(title):
    result = subprocess.run(
        ["zenity", "--password", f"--title={title}"],
        stdout=subprocess.PIPE,
        check=False,
    )
    password = result.stdout.rstrip(b"\n")
    if result.returncode or not password:
        raise RuntimeError("A nonempty keyring password is required")
    return password


def main():
    os.umask(0o077)
    keyring = Path.home() / ".local/share/keyrings/login.keyring"
    existing = keyring.is_file()
    bus = dbus.SessionBus()
    if not ready(bus) and "--check" in sys.argv:
        raise RuntimeError("Keyring is locked")
    if not ready(bus):
        password = prompt("Unlock Signal keyring")
        if not existing and password != prompt("Confirm Signal keyring password"):
            raise RuntimeError("The passwords do not match")
        subprocess.run(["gnome-keyring-daemon", "--replace", "--unlock", "--components=secrets"], input=password,
                       stdout=subprocess.DEVNULL, check=True)
        del password
        for _ in range(50):
            try:
                if ready(bus):
                    break
            except dbus.DBusException:
                pass
            time.sleep(0.1)
    if not ready(bus):
        raise RuntimeError("Incorrect keyring password; Signal was not started" if existing
                           else "Could not unlock the new keyring; Signal was not started")
    # A blank-password keyring is plaintext, even though Secret Service reports
    # it unlocked. Reject it before Signal ever creates its database key.
    if not keyring.is_file() or not keyring.read_bytes().startswith(b"GnomeKeyring\n\r\0\n"):
        raise RuntimeError("Signal requires an encrypted login keyring")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, dbus.DBusException, subprocess.SubprocessError) as error:
        print(f"Signal keyring: {error}", file=sys.stderr)
        sys.exit(1)
