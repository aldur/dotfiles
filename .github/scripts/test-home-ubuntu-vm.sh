#!/usr/bin/env bash
# An actual Ubuntu cloud guest: no Nix, account ubuntu, SSH/PAM and a reboot.
set -euo pipefail
work=${RUNNER_TEMP:-/tmp}/dotfiles-ubuntu-bootstrap
mkdir -p "$work/logs"
[[ ! -e $work/disk.qcow2 ]] || {
  echo "Use a fresh RUNNER_TEMP; $work already contains a VM." >&2
  exit 1
}
port=${DOTFILES_VM_PORT:-22725}
vm_pid=''
agent_pid=''
ssh_args=(-F /dev/null -i "$work/ssh_key" -p "$port" -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$work/known_hosts"
  -o ConnectTimeout=5 -o BatchMode=yes)
# Arguments intentionally contain commands for the remote shell.
# shellcheck disable=SC2029
remote() { ssh "${ssh_args[@]}" ubuntu@127.0.0.1 "$@"; }
cleanup() {
  result=$?
  trap - EXIT
  remote 'sudo journalctl -b --no-pager -n 300' >"$work/logs/journal.txt" 2>&1 || true
  [[ -z $vm_pid ]] || kill "$vm_pid" 2>/dev/null || true
  [[ -z $agent_pid ]] || kill "$agent_pid" 2>/dev/null || true
  if ((result != 0)); then tail -n 80 "$work/logs"/*.log; fi
  exit "$result"
}
trap cleanup EXIT

image_name=noble-server-cloudimg-amd64.img
image_url=https://cloud-images.ubuntu.com/noble/current
curl --fail --location --retry 3 "$image_url/SHA256SUMS" -o "$work/SHA256SUMS"
if [[ -n ${DOTFILES_VM_IMAGE:-} ]]; then
  ln -s "$(realpath "$DOTFILES_VM_IMAGE")" "$work/$image_name"
else
  curl --fail --location --retry 3 "$image_url/$image_name" -o "$work/$image_name"
fi
(
  cd "$work"
  grep -E " [*]?$image_name$" SHA256SUMS | sha256sum --check
)
qemu-img create -f qcow2 -F qcow2 -b "$work/$image_name" "$work/disk.qcow2" 64G
ssh-keygen -q -t ed25519 -N '' -f "$work/ssh_key"
cat >"$work/user-data" <<CLOUD
#cloud-config
users:
  - default
ssh_authorized_keys:
  - $(cat "$work/ssh_key.pub")
ssh_pwauth: false
package_update: false
CLOUD
printf 'instance-id: dotfiles-bootstrap\nlocal-hostname: dotfiles-bootstrap\n' >"$work/meta-data"
genisoimage -quiet -output "$work/seed.iso" -volid cidata -joliet -rock "$work/user-data" "$work/meta-data"
accel=tcg
[[ ! -r /dev/kvm || ! -w /dev/kvm ]] || accel=kvm
qemu-system-x86_64 -machine "q35,accel=$accel" -cpu max -smp 4 -m 8192 \
  -drive "file=$work/disk.qcow2,if=virtio,format=qcow2" \
  -drive "file=$work/seed.iso,media=cdrom,readonly=on" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$port-:22" \
  -device virtio-net-pci,netdev=net0 -display none \
  -serial "file:$work/logs/serial.log" >"$work/logs/qemu.log" 2>&1 &
vm_pid=$!
wait_ssh() {
  local deadline=$((SECONDS + 300))
  until remote true 2>/dev/null; do
    kill -0 "$vm_pid"
    ((SECONDS < deadline)) || {
      echo 'Timed out waiting for SSH.' >&2
      return 1
    }
    sleep 2
  done
}
wait_ssh
# shellcheck disable=SC2016
remote 'cloud-init status --wait && test ! -e /nix && test "$(id -un)" = ubuntu' >"$work/logs/before.log" 2>&1
# Copy the working tree, including the bootstrap under test, without local state.
git ls-files -z --cached --others --exclude-standard |
  tar --exclude=.lazygit.yml --null --files-from=- -czf "$work/repo.tar.gz"
remote 'mkdir -p ~/dotfiles; tar -xzf - -C ~/dotfiles' <"$work/repo.tar.gz"
# CI's shared egress can exhaust the GitHub API quota. The existing action
# verifies these public keys against the lock; retain that hash in the guest.
if [[ -n ${SIGNING_KEYS:-} ]]; then
  remote 'cat > ~/ssh_signing_keys.json' <"$SIGNING_KEYS"
  remote python3 - <<'PY'
import json
from pathlib import Path
path = Path.home() / "dotfiles/flake.lock"
lock = json.loads(path.read_text())
lock["nodes"]["gh-signing-keys"]["locked"]["url"] = (Path.home() / "ssh_signing_keys.json").as_uri()
path.write_text(json.dumps(lock, indent=2) + "\n")
PY
fi
remote 'mkdir -p ~/.config/fish; echo "# pre-existing config" > ~/.config/fish/config.fish; echo preserved > ~/unmanaged-marker'
echo "Booted fresh Ubuntu without Nix ($accel). Running the documented bootstrap..."
# The local file URL supplies the checkout under test through the documented pipe.
remote 'bash -o pipefail -c "curl -fsSL file:///home/ubuntu/dotfiles/base_hosts/home-manager/bootstrap.sh | bash -s -- --source path:/home/ubuntu/dotfiles"' >"$work/logs/bootstrap.log" 2>&1
remote 'bash -o pipefail -c "curl -fsSL file:///home/ubuntu/dotfiles/base_hosts/home-manager/bootstrap.sh | bash"' >"$work/logs/repeat.log" 2>&1

# Only a disposable signing key crosses into the guest, through agent forwarding.
eval "$(ssh-agent -s)" >/dev/null
agent_pid=$SSH_AGENT_PID
ssh-add "$work/ssh_key" 2>/dev/null
ssh_args+=(-A)
before=$(remote 'cat /proc/sys/kernel/random/boot_id')
remote 'sudo reboot' || true
deadline=$((SECONDS + 300))
while true; do
  after=$(remote 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
  [[ -z $after || $after == "$before" ]] || break
  ((SECONDS < deadline)) || {
    echo 'Guest did not reboot.' >&2
    exit 1
  }
  sleep 2
done
echo 'Reconnected after reboot. Checking the real login environment...'
# SSH invokes the configured login shell; no manually supplied PATH/XDG variables.
# shellcheck disable=SC2016
remote 'test "$SHELL" = "$HOME/.nix-profile/bin/fish"; and fish --login --interactive --command "type -q ta; and type -q tls; and test \$EDITOR = nvim"' >"$work/logs/login.log" 2>&1
remote 'bash ~/dotfiles/.github/scripts/test-home-ubuntu-login.sh' >"$work/logs/smoke.log" 2>&1
printf 'PASS: fresh Ubuntu, Nix installation, ubuntu account, repeated activation, reboot, SSH, services, sandbox and signed Git commit.\n' | tee "$work/logs/result.log"
