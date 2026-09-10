set -euo pipefail
[[ $(/usr/sbin/sysctl -n hw.model) == VirtualMac* ]] || {
  echo 'macos-vm bootstrap must run inside an Apple Virtualization guest' >&2
  exit 1
}
# Tart grows the disk image; macOS must also grow its APFS container.
disk_info=$(mktemp -t macos-vm-disk-info)
trap 'rm -f "$disk_info"' EXIT
/usr/sbin/diskutil info -plist / > "$disk_info"
container=$(/usr/libexec/PlistBuddy -c 'Print :APFSContainerReference' "$disk_info")
/usr/sbin/diskutil info -plist "$container" > "$disk_info"
physical_store=$(/usr/libexec/PlistBuddy -c 'Print :APFSPhysicalStores:0:APFSPhysicalStore' "$disk_info")
/usr/sbin/diskutil info -plist "$physical_store" > "$disk_info"
physical_disk=$(/usr/libexec/PlistBuddy -c 'Print :ParentWholeDisk' "$disk_info")
printf 'y\n' | sudo -n /usr/sbin/diskutil repairDisk "$physical_disk"
/usr/sbin/diskutil apfs resizeContainer "$container" limits -plist > "$disk_info"
current_size=$(/usr/libexec/PlistBuddy -c 'Print :CurrentSize' "$disk_info")
maximum_size=$(/usr/libexec/PlistBuddy -c 'Print :MaximumSize' "$disk_info")
# Tahoe's grow-to-fit request can exceed its own aligned maximum. Leave a
# small alignment margin, and never shrink an already larger container.
target_size=$(( (maximum_size / 1048576 - 16) * 1048576 ))
if (( target_size > current_size )); then
  if ! resize_output=$(sudo -n /usr/sbin/diskutil apfs resizeContainer "$container" "${target_size}B" 2>&1); then
    echo "$resize_output" >&2
    # Tahoe can finish the expansion at reboot while live diskutil reports a
    # stale layout. Ask the launcher for one reboot, then recheck the sizes.
    if [[ "$resize_output" == *'Error: -69606:'* || "$resize_output" == *'Error: -69808:'* ]]; then
      exit 75
    fi
    exit 1
  fi
fi
if [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  installer=$(mktemp -t macos-vm-nix-install)
  trap 'rm -f "$installer" "$disk_info"' EXIT
  /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
    https://releases.nixos.org/nix/nix-2.35.2/install -o "$installer"
  printf '%s  %s\n' 9adda97297d9e8ab360df95c729eabff4f4f93d6db091953c3a68f29e3fb130c "$installer" |
    /usr/bin/shasum -a 256 -c -
  /bin/sh "$installer" --daemon --yes --darwin-use-unencrypted-nix-store-volume </dev/null
fi
# The pinned installer appends its environment setup to Apple's shell files.
# Preserve those generated files before nix-darwin takes ownership on first use.
if [[ ! -e /run/current-system ]]; then
  for profile in /etc/bashrc /etc/zshrc; do
    if [[ -f "$profile" && ! -L "$profile" ]] &&
      /usr/bin/grep -q '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' "$profile"; then
      sudo -n /bin/mv -n "$profile" "$profile.before-nix-darwin"
    fi
  done
fi
sudo -n /usr/bin/install -d -m 0755 /usr/local/libexec
printf '%s\n' '#!/bin/sh' 'exec sudo -H -n /nix/var/nix/profiles/default/bin/nix-daemon "$@"' |
  sudo -n /usr/bin/tee /usr/local/libexec/macos-vm-nix-daemon >/dev/null
sudo -n /bin/chmod 0755 /usr/local/libexec/macos-vm-nix-daemon
