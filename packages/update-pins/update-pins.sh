#!/usr/bin/env bash

set -euo pipefail

# Run the bump legs of the flake in the current directory. The flake must
# export `updatePins`; see README.md next to this script. Each leg carries
# its `bump` and `verify` commands, and this script runs them verbatim.

# @describe Run the `updatePins` bump legs of the flake in the current directory
# @flag --no-cooldown Take the newest upstream state, also if it is new
# @arg packages* The names of the legs to run; with no names, list the legs

declare -a argc_packages=()
declare argc_no_cooldown=0
eval "$(argc --argc-eval "$0" "$@")"

legs=$(nix eval --json .#updatePins)

if [ "${#argc_packages[@]}" -eq 0 ]; then
  echo "usage: update-pins <package> [package ...]" >&2
  echo >&2
  echo "Available legs:" >&2
  jq -r '.[] | [.package, .runner] | @tsv' <<<"$legs" >&2
  exit 1
fi

for package in "${argc_packages[@]}"; do
  leg=$(jq -c --arg p "$package" '.[] | select(.package == $p)' <<<"$legs")
  if [ -z "$leg" ]; then
    echo "error: no leg is named '$package'" >&2
    echo >&2
    echo "Available legs:" >&2
    jq -r '.[].package' <<<"$legs" >&2
    exit 1
  fi

  runner=$(jq -r '.runner' <<<"$leg")
  os=$(jq -r '.os' <<<"$leg")
  bump=$(jq -r '.bump' <<<"$leg")
  verify=$(jq -r '.verify' <<<"$leg")

  if [ "$(uname -s)" != "$os" ]; then
    echo "skip: CI bumps '$package' on $runner" >&2
    continue
  fi

  # A leg with a cooldown takes the newest upstream state that is old
  # enough. cooldown.py selects it and prints the nix-update argument.
  cooldown=$(jq -c '.cooldown // empty' <<<"$leg")
  if [ -n "$cooldown" ] && [ "$argc_no_cooldown" -eq 0 ]; then
    version=$(update-pins-cooldown <<<"$cooldown")
    if [ -z "$version" ]; then
      echo "skip: '$package' has no update older than $(jq -r '.days' <<<"$cooldown") days" >&2
      continue
    fi
    bump="$bump $version"
  fi

  (
    set -x
    eval "$bump"
  )
  (
    set -x
    eval "$verify"
  )
done
