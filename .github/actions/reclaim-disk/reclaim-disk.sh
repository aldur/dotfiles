#!/usr/bin/env bash
# Make tens of gigabytes free on the Ubuntu runners of GitHub. Remove the
# toolchains and the docker caches that come with the runner. This repository
# does not use them.
set -euo pipefail

minimum=${MINIMUM_FREE_GIB:-64}
[[ $minimum =~ ^[0-9]+$ ]] || { echo 'minimum-free-gib must be an integer.' >&2; exit 1; }
available=$(df -Pk /nix/store | awk 'NR == 2 { print $4 }')
if ((available >= minimum * 1024 * 1024)); then
  echo "At least $minimum GiB is free; skip cleanup."
  exit 0
fi

df -h /
sudo rm -rf /usr/lib/jvm /usr/share/dotnet /usr/share/swift /usr/local/.ghcup /usr/local/julia* \
  /usr/local/lib/android /usr/local/share/chromium /opt/microsoft /opt/google \
  /opt/az /usr/local/share/powershell /opt/hostedtoolcache
docker system prune -af || true
docker builder prune -af || true
df -h /
