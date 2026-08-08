#!/usr/bin/env bash
# Build all the checks that the flake exports for the specified system. The
# flake-check job only evaluates the checks (`--no-build`). This script
# builds them.
set -euo pipefail

system=${1:?system is necessary, for example x86_64-linux}

nix eval --json ".#checks.$system" --apply builtins.attrNames \
  | jq -r --arg s "$system" '.[] | ".#checks.\($s)." + .' \
  | xargs -r nix build
