#!/usr/bin/env bash
# Build the checks that the flake exports for the specified system. The
# flake-check job only evaluates the checks (`--no-build`). This script
# builds them.
#
# A check can require a system feature, for example `kvm` for a NixOS VM
# test. The arm64 GitHub runners have no KVM. The script skips a check that
# requires a feature the daemon does not have, and prints a notice for it.
#
# The second argument selects a shard. A VM test and the rest of the checks
# share almost no build: of the 889 paths that a cold runner builds, 321 are
# for the VM test alone, 585 for the other checks, and 17 for both. Two
# runners therefore finish much sooner than one, and the VM test no longer
# competes for CPU with the Rust and neovim builds. That competition starved
# the test driver and stalled it for the full test timeout.
set -euo pipefail

system=${1:?system is necessary, for example x86_64-linux}
shard=${2:-all}

case "$shard" in
  all | vm | rest) ;;
  *)
    echo "shard must be all, vm or rest, not $shard" >&2
    exit 1
    ;;
esac

# With $SIGNING_KEYS set, point the `gh-signing-keys` input at the local
# copy from `fetch-signing-keys.sh`. This stops an unauthenticated fetch
# of api.github.com, which hits the shared rate limit.
override=()
if [ -n "${SIGNING_KEYS:-}" ]; then
  override=(--override-input gh-signing-keys "file+file://$SIGNING_KEYS")
fi

# The derivation path of each check. The check derivation is lazy and does
# not show its attributes, so `nix derivation show` reads the required
# features from the derivation itself. Its output uses the base name of the
# derivation path as the key.
drvs=$(nix eval --json ".#checks.$system" "${override[@]}" \
  --apply 'checks: builtins.mapAttrs (_: check: check.drvPath) checks')
available=$(nix config show system-features | jq -R 'split(" ")')

# Build the derivation paths, not the flake attributes. A `nix build` on the
# attributes evaluates the flake a second time, and the client keeps that
# memory (about 5 GiB for these checks) for the full build. A large build,
# for example a Rust package, then has less memory on the 16 GiB runner.
#
# `kvm` in the required features marks a VM test. A new VM test therefore
# lands in the `vm` shard on its own.
targets=()
while IFS=$'\t' read -r name drv missing; do
  if [ -n "$missing" ]; then
    echo "::notice::Skip checks.$system.$name: the runner has no system feature: $missing"
  else
    targets+=("$drv^*")
  fi
done < <(jq -r '.[]' <<< "$drvs" | xargs nix derivation show \
  | jq -r --argjson drvs "$drvs" --argjson available "$available" --arg shard "$shard" '
  .derivations as $shown
  | $drvs | to_entries[]
  | ($shown[.value | split("/") | last].env.requiredSystemFeatures // "") as $required
  | ($required | split(" ") | any(. == "kvm")) as $isVM
  | select($shard == "all" or ($shard == "vm") == $isVM)
  | (($required | split(" ") | map(select(. != ""))) - $available) as $missing
  | "\(.key)\t\(.value)\t\($missing | join(" "))"')

# An empty shard is not a failure: an arm64 runner has no KVM, and `nix
# build` with no target would build the default package.
if [ ${#targets[@]} -eq 0 ]; then
  echo "::notice::No check to build for shard $shard on $system"
  exit 0
fi

nix build "${targets[@]}"
