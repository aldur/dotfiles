#!/usr/bin/env bash

set -euo pipefail

# @describe Copy text (or stdin) to the system clipboard with OSC 52
#
# OSC 52 works over SSH and through tmux (`set-clipboard on` forwards the
# sequence to the outer terminal).
#
# The sequence is written to the controlling terminal rather than stdout, so
# it still reaches the terminal when a caller captures stdout — which is how
# lazygit and friends run `os.copyToClipboardCmd`.
# @arg text* Text to copy; with no arguments, read stdin

declare -a argc_text=()
eval "$(argc --argc-eval "$0" "$@")"

# `base64 | tr -d '\n'` not `base64 -w 0`: -w is GNU-only and macOS
# /usr/bin/base64 rejects it. tr gives single-line output on both.
if [ "${#argc_text[@]}" -gt 0 ]; then
    encoded=$(printf '%s' "${argc_text[*]}" | base64 | tr -d '\n')
else
    # Encode stdin directly: command substitution of raw data drops newlines.
    encoded=$(base64 | tr -d '\n')
fi

# Terminals cap how long an OSC string they will buffer (tmux included), and
# silently drop anything past it — say so rather than appearing to succeed.
if [ "${#encoded}" -gt 100000 ]; then
    echo "tcopy: payload is ${#encoded} bytes encoded; the terminal will likely truncate it" >&2
fi

osc52() { printf '\033]52;c;%s\007' "$1"; }

# Try the controlling terminal, fall back to stdout. Testing `[ -w /dev/tty ]`
# first would not work: the device node exists and is writable even when the
# process has no controlling terminal, where the open fails with ENXIO — so
# attempt the write and let it fail.
if ! { osc52 "$encoded" > /dev/tty; } 2>/dev/null; then
    osc52 "$encoded"
fi
