#!/usr/bin/env bash
# Print the free memory and disk space of the runner each 15 seconds, with
# the three processes that use the most memory. A runner with no free
# memory stops with no Nix error in the log, and the steps after it do not
# run. Start the script in the background of the build step: its lines then
# go to the log of that step, up to the moment the runner stops.
set -euo pipefail

while true; do
  mem=$(awk '/MemAvailable/ { print int($2 / 1024) }' /proc/meminfo)
  disk=$(df -h --output=avail / | tail -n 1 | tr -d ' ')
  top=$(ps -eo rss=,comm= --sort=-rss | head -n 3 \
    | awk '{ printf "%s=%dMiB ", $2, $1 / 1024 }')
  printf 'resources %s mem-avail=%sMiB disk-avail=%s top: %s\n' \
    "$(date -u +%T)" "$mem" "$disk" "$top"
  sleep 15
done
