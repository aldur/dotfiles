#!/usr/bin/env bash
# Keep old exact-path policies so other users and rollback generations work.
set -euo pipefail
bwrap=${1:?expected the configured bubblewrap executable}
[[ $bwrap =~ ^/nix/store/[a-z0-9]{32}-bubblewrap-[^/]+/bin/bwrap$ && -x $bwrap ]]
if [[ $(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0) == 1 ]]; then
  package=${bwrap#/nix/store/}
  profile="dotfiles-${package%%/*}"
  policy=$(mktemp)
  trap 'rm -f "$policy"' EXIT
  cat >"$policy" <<POLICY
abi <abi/4.0>,
include <tunables/global>
profile $profile "$bwrap" flags=(unconfined) {
  userns,
}
POLICY
  sudo install -m 644 "$policy" "/etc/apparmor.d/$profile"
  sudo apparmor_parser -r "/etc/apparmor.d/$profile"
fi
