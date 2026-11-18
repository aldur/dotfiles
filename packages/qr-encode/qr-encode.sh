#!/usr/bin/env bash

set -euo pipefail

# @describe Encode text in a QR code. Print it to the terminal, or write a PNG image.
# @arg text Text to encode (reads stdin if not given)
# @option -o --output <FILE> Write a PNG image to FILE
# @flag --invert Print dark modules for terminals with a light background

# Declare variables not to trip shellcheck.
declare argc_text argc_output argc_invert
eval "$(argc --argc-eval "$0" "$@")"

args=()
if [[ -n "${argc_text:-}" ]]; then
  args+=("$argc_text")
fi

if [[ -n "${argc_output:-}" ]]; then
  qrtool encode -t png -o "$argc_output" "${args[@]}"
elif [[ -t 1 ]]; then
  type=unicode
  if [[ "${argc_invert:-0}" == 1 ]]; then
    type=unicode-invert
  fi
  qrtool encode -t "$type" "${args[@]}"
else
  # Stdout is not a terminal: write the PNG image to the pipe or file.
  qrtool encode -t png "${args[@]}"
fi
