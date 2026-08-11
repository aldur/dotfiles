# Run the bump legs of the flake in the current directory. The flake must
# export `updatePins`; see README.md next to this script. Each leg carries
# its `bump` and `verify` commands, and this script runs them verbatim.

legs=$(nix eval --json .#updatePins)

if [ $# -eq 0 ]; then
  echo "usage: update-pins <package> [package ...]" >&2
  echo >&2
  echo "Available legs:" >&2
  jq -r '.[] | [.package, .runner] | @tsv' <<<"$legs" >&2
  exit 1
fi

for package in "$@"; do
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

  (
    set -x
    eval "$bump"
  )
  (
    set -x
    eval "$verify"
  )
done
