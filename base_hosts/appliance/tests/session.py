import shlex


def session():
    machine.wait_for_unit("graphical.target")
    machine.wait_until_succeeds(f"pgrep -u {user} -f xfce4-session")
    environ = machine.succeed(
        f"cat /proc/$(pgrep -u {user} -f xfce4-session | head -n1)/environ | tr '\\0' '\\n'"
    )
    return " ".join(shlex.quote(line) for line in environ.splitlines()
                    if line.startswith(("DISPLAY=", "XAUTHORITY=", "DBUS_SESSION_BUS_ADDRESS=", "XDG_RUNTIME_DIR=")))


def as_user(command):
    return f"runuser -u {user} -- env HOME=/home/{user} {env} sh -c {shlex.quote(command)}"
