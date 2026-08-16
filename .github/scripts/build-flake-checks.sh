#!/usr/bin/env bash
# Build all the checks that the flake exports for the specified system. The
# flake-check job only evaluates the checks (`--no-build`). This script
# builds them.
set -euo pipefail

system=${1:?system is necessary, for example x86_64-linux}

# With $SIGNING_KEYS set, point the `gh-signing-keys` input at the local
# copy from `fetch-signing-keys.sh`. This stops an unauthenticated fetch
# of api.github.com, which hits the shared rate limit.
override=()
if [ -n "${SIGNING_KEYS:-}" ]; then
  override=(--override-input gh-signing-keys "file+file://$SIGNING_KEYS")
fi

nix eval --json ".#checks.$system" --apply builtins.attrNames "${override[@]}" \
  | jq -r --arg s "$system" '.[] | ".#checks.\($s)." + .' \
  | xargs -r nix build "${override[@]}"
