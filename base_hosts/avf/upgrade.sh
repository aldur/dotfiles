#!/usr/bin/env bash
set -euo pipefail

# @describe Upgrade this guest to the system of an avf-image tarball, without a build. Run it as root: `ssh root@.host avf-upgrade`.
# @arg image Tarball or artifact zip (default: /mnt/shared/Download/avf_image.tar.gz or avf-arm64.zip)
# @option --action[=switch|boot|test] Action of nixos-rebuild

declare argc_image argc_action
eval "$(argc --argc-eval "$0" "$@")"

die() {
  echo "$*" >&2
  exit 1
}

[[ $EUID == 0 ]] || die 'Run this as root: ssh root@.host avf-upgrade'

download=/mnt/shared/Download
image=${argc_image:-}
if [[ -z $image ]]; then
  for image in "$download/avf_image.tar.gz" "$download/avf-arm64.zip"; do
    [[ -f $image ]] && break
  done
fi
[[ -f $image ]] || die "No image at $image"

tarball() {
  if [[ $image == *.zip ]]; then
    unzip -p "$image" avf_image.tar.gz
  else
    cat "$image"
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Skip the files that exist: they are in valid store paths, or in paths that
# an interrupted run left. The verification below finds the second case.
# The store is a read-only bind mount. Make it writable only for tar, as
# nix-daemon does.
echo "Extracting the missing store paths from $image"
if ! tarball | unshare --mount "$BASH" -c 'mount -o remount,rw,bind /nix/store && exec "$@"' bash \
  tar -xzpf - -C / --numeric-owner --skip-old-files \
  --transform="s,^nix-path-registration\$,${work#/}/registration,;s,^nixos-system\$,${work#/}/system," \
  nix nix-path-registration nixos-system; then
  die 'Extraction failed. Run nix-store --gc to remove the partial paths. If the disk is full, resize it in Terminal settings.'
fi

system=$(readlink "$work/system")
nix-store --load-db < "$work/registration"
echo "Verifying the closure of $system"
nix-store --query --requisites "$system" | xargs nix-store --verify-path ||
  die 'Some store paths are not correct. Run nix-store --gc, then run avf-upgrade again.'

# Without --no-reexec, nixos-rebuild builds itself first.
nixos-rebuild "$argc_action" --no-reexec --store-path "$system"
