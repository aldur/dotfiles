#!/usr/bin/env bash
# Replaces the Debian guest of the Android Terminal app with the NixOS
# tarball of `avf-image`. Run it in the Debian guest, as the `droid` user.
# See base_hosts/avf/README.md.
set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

tarball=${1:-/mnt/shared/Download/avf_image.tar.gz}
[[ -f $tarball ]] || die "Usage: $0 [TARBALL] (default: $tarball)"
[[ $(findmnt -n -o SOURCE /) == /dev/vda1 ]] ||
  die 'Run this in the Debian guest of the Terminal app.'
[[ ! -e /nix ]] || die '/nix exists. Reset the guest in Terminal settings first.'

echo "Extracting $tarball"
if ! sudo tar -xzpf "$tarball" -C / --numeric-owner \
  nix nix-path-registration nixos-lustrate-init; then
  sudo rm -rf /nix /nix-path-registration /nixos-lustrate-init
  die 'Extraction failed. If the disk is full, resize it in Terminal settings.'
fi

init=$(readlink /nixos-lustrate-init)
[[ -x $init ]] || die "Missing init in the tarball: $init"
# /sbin links to usr/sbin. The kernel starts /sbin/init.
sudo ln -sfn "$init" /usr/sbin/init
sync

echo 'The guest stops now. Open Terminal again to start NixOS.'
sudo reboot
