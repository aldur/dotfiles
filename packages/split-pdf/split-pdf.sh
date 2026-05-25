#!/usr/bin/env bash

set -euo pipefail

# @describe Split a PDF into one file per page
# @arg input! Input PDF file
# @arg output Output filename pattern with %d for page number (defaults to <input>-page-%d.pdf)

# Declare variables not to trip shellcheck.
declare argc_input argc_output
eval "$(argc --argc-eval "$0" "$@")"

if [[ ! -f "$argc_input" ]]; then
  echo "Error: File '$argc_input' does not exist" >&2
  exit 1
fi

if [[ -n "${argc_output:-}" ]]; then
  pattern="$argc_output"
else
  base="${argc_input%.pdf}"
  pattern="${base}-page-%d.pdf"
fi

qpdf "$argc_input" --split-pages "$pattern"
echo "Split PDF written to: $pattern"
