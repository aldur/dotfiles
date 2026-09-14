#!/usr/bin/env bash
# Make tens of gigabytes free on the Ubuntu runners of GitHub. Remove the
# toolchains and the docker caches that come with the runner. This repository
# does not use them.
set -euo pipefail

df -h /
sudo rm -rf /usr/lib/jvm /usr/share/dotnet /usr/share/swift /usr/local/.ghcup /usr/local/julia* \
  /usr/local/lib/android /usr/local/share/chromium /opt/microsoft /opt/google \
  /opt/az /usr/local/share/powershell /opt/hostedtoolcache
docker system prune -af || true
docker builder prune -af || true
df -h /
