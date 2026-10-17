pid=$(runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" systemctl --user show signal -p MainPID --value)
uid=$(id -u "$user")
gid=$(id -g "$user")
# Use both namespaces and the app's UID. Root-only bus failures prove nothing.
nsenter -t "$pid" -U -m --setuid="$uid" --setgid="$gid" -- \
  env HOME="/home/$user" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
  bash -euo pipefail -c '
    test "$(id -u)" = "$1"
    test ! -e "$XDG_RUNTIME_DIR/systemd/private"
    test ! -e "$XDG_RUNTIME_DIR/keyring/control"
    busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service ReadAlias s default | grep /collection/
    if systemd-run --user --wait --unit=signal-escape touch "$HOME/escaped-sandbox"; then exit 1; fi
    if busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager ListUnits; then exit 1; fi
  ' bash "$uid"
test ! -e "/home/$user/escaped-sandbox"
dns_pid=$(systemctl show dnsmasq -p MainPID --value)
test "$(ps -o uid= -p "$dns_pid" | xargs)" = "$(id -u dnsmasq)"
grep -q '^NoNewPrivs:[[:space:]]*1$' "/proc/$dns_pid/status"
grep -q '^Seccomp:[[:space:]]*2$' "/proc/$dns_pid/status"
grep -q '^CapBnd:[[:space:]]*00000000000004c0$' "/proc/$dns_pid/status"
if nsenter -t "$dns_pid" -m -- touch /etc/dnsmasq-forbidden; then exit 1; fi
nsenter -t "$dns_pid" -m -- touch /var/lib/dnsmasq/write-probe
rm /var/lib/dnsmasq/write-probe
