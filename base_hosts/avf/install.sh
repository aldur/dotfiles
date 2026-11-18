#!/usr/bin/env bash
# Replaces the Debian guest of the Android Terminal app with the NixOS
# tarball of `avf-image`. Run it in the Debian guest, as the `droid` user.
# See base_hosts/avf/README.md.
set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

download=/mnt/shared/Download
# The browser saves the artifact of the avf-image workflow as a zip.
image=${1:-}
if [[ -z $image ]]; then
  for image in "$download/avf_image.tar.gz" "$download/avf-arm64.zip"; do
    [[ -f $image ]] && break
  done
fi
[[ -f $image ]] ||
  die "Usage: $0 [IMAGE] (default: $download/avf_image.tar.gz or $download/avf-arm64.zip)"
[[ $(findmnt -n -o SOURCE /) == /dev/vda1 ]] ||
  die 'Run this in the Debian guest of the Terminal app.'
[[ ! -e /nix ]] || die '/nix exists. Reset the guest in Terminal settings first.'

# The Debian guest does not always have unzip. It has python3 for cloud-init.
tarball() {
  if [[ $image == *.zip ]]; then
    python3 -c 'import shutil, sys, zipfile
shutil.copyfileobj(zipfile.ZipFile(sys.argv[1]).open("avf_image.tar.gz"), sys.stdout.buffer)' "$image"
  else
    cat "$image"
  fi
}

echo "Extracting $image"
if ! tarball | sudo tar -xzpf - -C / --numeric-owner \
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
