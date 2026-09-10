# @describe Run a macOS VM with the repository's nix-darwin configuration
# @option -d --dir <DIR> VM state and image cache directory
# @option --name <NAME> VM name (default: macos)
# @option -m --memory <MB> Memory in MB (default: 8192)
# @option --cores <N> CPU cores (default: 4)
# @option --disk-size <GB> Grow the virtual disk (never shrink it)
# @option --image <IMAGE> Prepared Tart image with guest agent, admin account and passwordless sudo
# @flag --gui Open the graphical window (headless by default)
# @flag --headless Run without a graphical window
# @flag --clipboard Enable clipboard sharing
# @flag --ip Print the existing VM's IP address and exit
# @flag --stop Stop the existing VM and exit
# @flag --ssh Connect to the configured guest over SSH
# @flag --check Verify the running guest's nix-darwin and Home Manager configuration

declare argc_dir argc_name argc_memory argc_cores argc_disk_size argc_image
declare argc_gui argc_headless argc_clipboard argc_ip argc_stop argc_ssh argc_check
eval "$(argc --argc-eval "$0" "$@")"

fail() { echo "macos-vm: $*" >&2; exit 1; }
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail "requires an Apple Silicon Mac"
vm_name="${argc_name:-macos}"
[[ "$vm_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail "invalid VM name"
[[ -z "${argc_gui:-}" || -z "${argc_headless:-}" ]] || fail "--gui and --headless are mutually exclusive"
management=0
for mode in "${argc_ip:-}" "${argc_stop:-}" "${argc_ssh:-}" "${argc_check:-}"; do
  [[ -z "$mode" ]] || management=$((management + 1))
done
(( management <= 1 )) || fail "choose only one of --ip, --stop, --ssh or --check"
memory="${argc_memory:-$default_memory}"
cores="${argc_cores:-$default_cores}"
disk_size="${argc_disk_size:-$default_disk_size}"
for value in "$memory" "$cores" "$disk_size"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "memory, cores and disk size must be positive integers"
done
default_dir="${default_dir/\$HOME/$HOME}"
export TART_HOME="${argc_dir:-$default_dir}"
export TART_NO_AUTO_PRUNE=1
umask 077
mkdir -p "$TART_HOME"
TART_HOME=$(realpath "$TART_HOME")
if [[ -n "${argc_ip:-}" ]]; then exec tart ip "$vm_name"; fi
if [[ -n "${argc_stop:-}" ]]; then exec tart stop "$vm_name"; fi

identity_dir="$TART_HOME/.macos-vm-$vm_name"
mkdir -p "$identity_dir"
ssh_config="$identity_dir/ssh_config"
key="$identity_dir/id_ed25519"

write_ssh_config() {
  local config_tmp proxy_command
  [[ "$identity_dir" != *'"'* && "$identity_dir" != *$'\n'* ]] || fail "unsupported quote or newline in state directory"
  config_tmp=$(mktemp "$identity_dir/ssh-config.XXXXXX")
  printf -v proxy_command '/usr/bin/env TART_HOME=%q %q exec -i %q /usr/bin/nc 127.0.0.1 22' \
    "$TART_HOME" "$(command -v tart)" "$vm_name"
  proxy_command="${proxy_command//%/%%}"
  {
    echo 'Host guest'
    echo '  HostName guest'
    echo "  ProxyCommand $proxy_command"
    echo '  User admin'
    echo "  HostKeyAlias macos-vm-$vm_name"
    printf '  IdentityFile "%s"\n' "$key"
    printf '  UserKnownHostsFile "%s/known_hosts"\n' "$identity_dir"
    echo '  StrictHostKeyChecking accept-new'
    echo '  IdentitiesOnly yes'
    echo '  IdentityAgent none'
    echo '  ConnectTimeout 30'
    echo '  ServerAliveInterval 15'
    echo '  ServerAliveCountMax 4'
    echo '  LogLevel ERROR'
  } > "$config_tmp"
  mv "$config_tmp" "$ssh_config"
}
guest_ssh() { ssh -F "$ssh_config" -o BatchMode=yes guest "$@"; }
check_guest() {
  guest_ssh /bin/bash -s -- "$guest_system" <<'CHECK'
set -euo pipefail
expected=$1
test "$(readlink /run/current-system)" = "$expected"
test "$(/usr/sbin/scutil --get HostName)" = macos-vm
test -L /Users/admin/.config/fish/config.fish
test -L /Users/admin/.config/git/config
export PATH=/run/current-system/sw/bin:/etc/profiles/per-user/admin/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin
/run/current-system/sw/bin/fish -lc 'git --version; and tmux -V; and command -v nvim; and command -v codex; and command -v claude'
/run/current-system/sw/bin/nix --version
/run/current-system/sw/bin/nix store info --json
sudo -n /usr/sbin/sshd -T | /usr/bin/grep '^passwordauthentication no$'
printf 'macos-vm: nix-darwin and Home Manager checks passed\n'
CHECK
}
if [[ -n "${argc_ssh:-}" || -n "${argc_check:-}" ]]; then
  [[ -f "$key" ]] || fail "guest has not been provisioned by this launcher"
  write_ssh_config
  if [[ -n "${argc_check:-}" ]]; then check_guest; exit; fi
  exec ssh -F "$ssh_config" -o BatchMode=yes guest
fi

lock_dir="$identity_dir/lock"
mkdir "$lock_dir" 2>/dev/null || fail "VM is in use; after a crash, verify it is stopped before removing $lock_dir"
vm_pid=""
stop_vm() {
  if [[ -n "$vm_pid" ]] && kill -0 "$vm_pid" 2>/dev/null; then
    tart exec "$vm_name" sudo -n /sbin/shutdown -h now >/dev/null 2>&1 || true
    for (( shutdown_wait=0; shutdown_wait<30; shutdown_wait++ )); do
      kill -0 "$vm_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$vm_pid" 2>/dev/null; then tart stop "$vm_name" >/dev/null 2>&1 || true; fi
    wait "$vm_pid" || true
  fi
  vm_pid=""
}
cleanup() {
  stop_vm
  rmdir "$lock_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -e "$TART_HOME/vms/$vm_name" ]]; then
  # Pin the prepared image used by the end-to-end test.
  tart clone "${argc_image:-ghcr.io/cirruslabs/macos-tahoe-base@sha256:1b093499716409d29e8b5336844528e1cae375db97d2ad8e5aeff78cf0da201e}" "$vm_name"
elif [[ -n "${argc_image:-}" ]]; then
  fail "VM already exists; choose a new --name to use another image"
fi
[[ -f "$key" ]] || ssh-keygen -q -t ed25519 -N '' -f "$key"
set_args=(--memory "$memory" --cpu "$cores")
if [[ -n "${argc_disk_size:-}" ]] ||
  (( $(stat -c %s "$TART_HOME/vms/$vm_name/disk.img") < disk_size * 1000000000 )); then
  set_args+=(--disk-size "$disk_size")
fi
tart set "$vm_name" "${set_args[@]}"
run_args=(--no-audio)
[[ -n "${argc_gui:-}" ]] || run_args+=(--no-graphics)
[[ -n "${argc_clipboard:-}" ]] || run_args+=(--no-clipboard)
tart run "$vm_name" "${run_args[@]}" &
vm_pid=$!
echo "Waiting for $vm_name to boot..." >&2
write_ssh_config

wait_for_guest() {
local ready=0 attempt
for (( attempt=0; attempt<120; attempt++ )); do
  kill -0 "$vm_pid" 2>/dev/null || fail "VM exited before SSH became available"
  if guest_ssh true 2>/dev/null; then ready=1; break; fi
  if tart exec -i "$vm_name" /bin/sh -c \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' < "$key.pub" 2>/dev/null; then
    if guest_ssh true 2>/dev/null; then ready=1; break; fi
  fi
  sleep 2
done
(( ready == 1 )) || fail "bootstrap timed out; the image must provide the Tart guest agent, admin account and passwordless sudo"
}
wait_for_guest

if ! guest_ssh "test \"\$(readlink /run/current-system)\" = '$guest_system'"; then
  echo "Provisioning Nix and your nix-darwin configuration..." >&2
  guest_ssh 'sudo -n /usr/bin/tee /etc/ssh/macos-vm-authorized-key >/dev/null' < "$key.pub"
  if guest_ssh /bin/bash -s < "$bootstrap_script"; then
    :
  else
    bootstrap_status=$?
    (( bootstrap_status == 75 )) || exit "$bootstrap_status"
    echo "Restarting once to finish APFS expansion..." >&2
    # Recreate Tart's control socket as well as rebooting macOS. The pinned
    # Tart release can lose that socket across an in-guest warm reboot.
    stop_vm
    tart run "$vm_name" "${run_args[@]}" &
    vm_pid=$!
    wait_for_guest
    guest_ssh /bin/bash -s < "$bootstrap_script"
  fi
  (
    cd "$identity_dir"
    # Import our locally built, unsigned outputs over the authenticated VM
    # connection. This only relaxes signature checks for this root transfer.
    NIX_SSHOPTS='-F ssh_config -o BatchMode=yes' \
      nix copy --no-check-sigs --to 'ssh-ng://guest?remote-program=/usr/local/libexec/macos-vm-nix-daemon' "$guest_system"
  )
  guest_ssh "sudo -H -n /nix/var/nix/profiles/default/bin/nix-env --profile /nix/var/nix/profiles/system --set '$guest_system' && sudo -H -n '$guest_system/activate'"
fi
check_guest
echo "Ready: macos-vm --dir $(printf '%q' "$TART_HOME") --name $vm_name --ssh" >&2
wait "$vm_pid"
