#!/usr/bin/env bash
# Write the free memory and disk space of the runner to $1 each 15 seconds.
# A runner with no free memory or disk stops with no Nix error in the job
# log. Start the script in the background. A step at the end of the job
# shows the file.
set -euo pipefail

log=${1:?log file is necessary}

while true; do
  mem=$(awk '/MemAvailable/ { print int($2 / 1024) }' /proc/meminfo)
  disk=$(df -h --output=avail / | tail -n 1 | tr -d ' ')
  printf '%s mem-avail=%sMiB disk-avail=%s\n' "$(date -u +%T)" "$mem" "$disk" >> "$log"
  sleep 15
done
