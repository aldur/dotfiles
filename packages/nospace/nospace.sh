#!/usr/bin/env bash

set -euo pipefail

# @describe Remove all whitespace, including line breaks, from text or stdin
# @arg text* Text to join; with no arguments, read stdin

declare -a argc_text=()
eval "$(argc --argc-eval "$0" "$@")"

if [ "${#argc_text[@]}" -gt 0 ]; then
    printf '%s' "${argc_text[@]}" | tr -d '[:space:]'
else
    tr -d '[:space:]'
fi
