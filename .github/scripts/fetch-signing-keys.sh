#!/usr/bin/env bash
# Fetch the keys behind the `gh-signing-keys` flake input into $SIGNING_KEYS,
# for callers to point the input at with `--override-input`.
#
# The input is a `type: file` URL on api.github.com, capped at 60
# unauthenticated requests/hour per IP — a budget shared with every other
# Actions job on the runner's egress address, so letting Nix fetch it was a
# coin flip. Nix can't authenticate it itself: `access-tokens` only reaches
# the `github:` fetcher, and the API ignores the Basic auth a netrc carries.
#
# `--override-input` takes an input unlocked, so re-pin the result against
# flake.lock rather than trusting whatever the API just returned.
set -euo pipefail

: "${GH_TOKEN:?token with API read access required}"
: "${SIGNING_KEYS:?destination path required}"

curl -sS --fail --retry 3 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    https://api.github.com/users/aldur/ssh_signing_keys \
    -o "$SIGNING_KEYS"

locked=$(jq -r '.nodes["gh-signing-keys"].locked.narHash' flake.lock)
got=$(nix hash path --type sha256 --sri "$SIGNING_KEYS")

if [ "$got" != "$locked" ]; then
    echo "::error::gh-signing-keys drifted from flake.lock ($got != $locked); run 'nix flake update gh-signing-keys'"
    exit 1
fi
