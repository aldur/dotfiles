#!/usr/bin/env bash

# @describe Apply default settings to Logitech C920 webcam
# @flag -q --quiet Suppress output
# @flag -n --dry-run Show commands without executing

declare argc_quiet argc_dry_run
eval "$(argc --argc-eval "$0" "$@")"

run_cmd() {
  if [[ "${argc_dry_run:-0}" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

log() {
  if [[ "${argc_quiet:-0}" -eq 0 ]]; then
    echo "$@"
  fi
}

# Check if camera is connected
if ! uvc-util -d 2>/dev/null | grep -q "HD Pro Webcam C920"; then
  echo "Error: Logitech C920 not found" >&2
  exit 1
fi

log "Applying C920 default settings..."

# Setting these is not currently supported
# -s white-balance-temp=3266
# -s exposure-time-abs=333 \
# -s focus-abs=0 \

run_cmd uvc-util -V 0x046d:0x082d \
  -s brightness=128 \
  -s contrast=128 \
  -s saturation=128 \
  -s sharpness=128 \
  -s gain=131 \
  -s auto-white-balance-temp=true \
  -s backlight-compensation=0 \
  -s zoom-abs=120 \
  -s "pan-tilt-abs={pan=-28800,tilt=-36000}" \
  -s auto-focus=true \
  -s auto-exposure-mode=8 \
  -s auto-exposure-priority=1 \
  -s power-line-frequency=2

log "Done."
