#!/usr/bin/env bash
set -euo pipefail

: "${user:?user must name the session account}"
: "${persist:?persist must list the directories relative to the home}"
home=$(getent passwd "$user" | cut -d: -f6)
uid=$(id -u "$user")
read -r -a directories <<< "$persist"

as_user() {
  runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

case "${1:?plant or verify required}" in
  plant)
    echo transient > /etc/appliance-state-probe
    echo transient > /root/appliance-state-probe
    mkdir -p /nix/var/appliance-state-probe
    for directory in "${directories[@]}"; do
      as_user touch "$home/$directory/.appliance-state-probe"
    done
    as_user mkdir -p "$home/.config/systemd/user"
    as_user tee "$home/.config/systemd/user/evil.service" > /dev/null <<'EOF'
[Unit]
Description=Must disappear before the next boot
[Service]
Type=oneshot
ExecStart=/run/current-system/sw/bin/touch %h/evil-ran
[Install]
WantedBy=default.target
EOF
    as_user systemctl --user daemon-reload
    as_user systemctl --user enable evil.service
    test -L "$home/.config/systemd/user/default.target.wants/evil.service"
    test ! -e "$home/evil-ran"
    echo 'PROBE state plant'
    ;;
  verify)
    for path in /etc/appliance-state-probe /root/appliance-state-probe \
      /nix/var/appliance-state-probe "$home/.config/systemd/user/evil.service" \
      "$home/.config/systemd/user/default.target.wants/evil.service" "$home/evil-ran"; do
      test ! -e "$path"
      test ! -L "$path"
    done
    state_device=$(stat -c %d /state)
    for directory in "${directories[@]}"; do
      test -f "$home/$directory/.appliance-state-probe"
      test "$(stat -c %d "$home/$directory")" = "$state_device"
    done
    test "$(stat -c %d "$home")" != "$state_device"
    root_type=$(findmnt -n -o FSTYPE /)
    case "$root_type" in overlay|tmpfs) ;; *) exit 1 ;; esac
    echo "PROBE state root $root_type"
    echo 'PROBE state verify'
    ;;
  *) exit 2 ;;
esac
