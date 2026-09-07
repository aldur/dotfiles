#!/usr/bin/env bash
# Build all the checks that the flake exports for the specified system. The
# flake-check job only evaluates the checks (`--no-build`). This script
# builds them.
#
# A check can require a system feature, for example `kvm` for a NixOS VM
# test. The arm64 GitHub runners have no KVM. The script skips a check that
# requires a feature the daemon does not have, and prints a notice for it.
set -euo pipefail

system=${1:?system is necessary, for example x86_64-linux}

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

targets=()
while IFS=$'\t' read -r name missing; do
  if [ -n "$missing" ]; then
    echo "::notice::Skip checks.$system.$name: the runner has no system feature: $missing"
  else
    targets+=(".#checks.$system.$name")
  fi
done < <(jq -r '.[]' <<< "$drvs" | xargs nix derivation show \
  | jq -r --argjson drvs "$drvs" --argjson available "$available" '
  .derivations as $shown
  | $drvs | to_entries[]
  | ($shown[.value | split("/") | last].env.requiredSystemFeatures // "") as $required
  | (($required | split(" ") | map(select(. != ""))) - $available) as $missing
  | "\(.key)\t\($missing | join(" "))"')

nix build "${override[@]}" "${targets[@]}"
