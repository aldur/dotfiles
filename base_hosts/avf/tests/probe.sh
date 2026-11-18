#!/bin/sh
# A stand-in for linux_vm_manager in the boot check of the image. It comes on
# the cidata disk, and the image starts it as it starts the agent. It makes
# the calls of the agent, writes one PROBE line for each check, and powers off
# the guest as the agent does.
set -u
# After the PATH of the agent, so that sudo and poweroff are those of the
# agent.
PATH=$PATH:/run/current-system/sw/bin
export XDG_RUNTIME_DIR=/run/user/1000
failures=0
trap 'echo "PROBE done failures=$failures"; poweroff' EXIT

check() {
  name=$1
  shift
  if output=$("$@" 2>&1); then
    echo "PROBE $name ok"
  else
    failures=$((failures + 1))
    echo "PROBE $name FAIL: $(echo "$output" | tr '\n' ' ')"
  fi
}
# Run COMMAND until it succeeds, for at most SECONDS.
retry() {
  seconds=$1
  shift
  while ! "$@"; do
    seconds=$((seconds - 1))
    [ "$seconds" -gt 0 ] || return 1
    sleep 1
  done
}
# The two calls of the agent.
clipboard() {
  sudo -u droid XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 "$@"
}

no_failed_units() {
  units=$(systemctl --failed --plain --no-legend)
  [ -z "$units" ] || {
    echo "$units"
    return 1
  }
}
agent_tools() {
  command -v sudo | grep -q -- -sudo/bin/sudo &&
    command -v poweroff | grep -q -- -poweroff/bin/poweroff
}
sbin_init() {
  grep -qx "exec $(readlink /run/current-system)/init" /sbin/init
}
paths_registered() {
  [ ! -e /nix-path-registration ] &&
    nix-store --check-validity "$(readlink -f /run/current-system)"
}
ttyd_vsock() {
  printf 'GET / HTTP/1.0\r\n\r\n' | socat -t5 - VSOCK-CONNECT:1:7681 | head -1 | grep -q ' 200 '
}
# The app waits 30 s for the terminal after the start of the VM.
ttyd_in_time() {
  [ "$(systemctl show -P ActiveEnterTimestampMonotonic ttyd-vsock-bridge.service)" -lt 30000000 ]
}
# wl-copy stays to serve the clipboard. As with the agent, it does not
# write to the output of the probe.
clipboard_write() {
  printf hello | clipboard wl-copy > /dev/null 2>&1
}
clipboard_read() {
  [ "$(clipboard wl-paste --no-newline)" = hello ]
}
sudo_refuses() {
  ! sudo -u root id
}
# fish reads environment.extraInit through /etc/profile.
login_environment() {
  environment=$(fish -l -c env)
  echo "$environment" | grep -qx WAYLAND_DISPLAY=wayland-0 &&
    echo "$environment" | grep -qx DISPLAY=:0
}
pipewire_has() {
  pw-dump | grep -q "\"media.class\": \"$1\""
}
tcpstates_header() {
  head -1 "$tcpstates_log" | grep -q LPORT
}
tcpstates_listen() {
  grep -Eq '8080 .*LISTEN' "$tcpstates_log"
}
storage_balloon() {
  read -r clusters < /sys/fs/ext4/vda1/reserved_clusters &&
    echo "$clusters" > /sys/fs/ext4/vda1/reserved_clusters
}
no_ssh_listener() {
  [ -z "$(ss -ltnH 'sport = :22')" ]
}

check system-running systemctl is-system-running --wait
check failed-units no_failed_units

# The agent unit.
check user [ "$(id -un)" = aldur ]
check no-new-privileges grep -q '^NoNewPrivs:[[:space:]]*1$' /proc/self/status
check no-capabilities grep -q '^CapEff:[[:space:]]*0*$' /proc/self/status
check agent-tools agent_tools
check cidata-copy [ -e /usr/lib64/probe-marker ]

# The installation and the first boot.
check old-root [ -e /old-root/etc/debian_version ]
check paths-registered paths_registered
check sbin-init sbin_init

# The terminal of the app.
check ttyd-vsock ttyd_vsock
check ttyd-in-time ttyd_in_time

# The display and the clipboard of the app.
check wayland retry 60 [ -S /run/user/1000/wayland-0 ]
check clipboard-write clipboard_write
check clipboard-read clipboard_read
check sudo-refuses sudo_refuses
check login-environment login_environment

# Sound on the virtio-snd card.
check audio-sink retry 30 pipewire_has Audio/Sink
check audio-source pipewire_has Audio/Source

# Port forwarding: the agent reads tcpstates as forwarder_guest_launcher does.
tcpstates_log=$RUNTIME_DIRECTORY/tcpstates
stdbuf -oL /usr/sbin/tcpstates-libbpf > "$tcpstates_log" 2>&1 &
tcpstates=$!
check tcpstates-header retry 30 tcpstates_header
socat TCP-LISTEN:8080,reuseaddr - > /dev/null &
listener=$!
check tcpstates-listen retry 30 tcpstates_listen
kill "$tcpstates" "$listener"

check storage-balloon storage_balloon
check zram grep -q zram /proc/swaps
check no-ssh-listener no_ssh_listener
