#!/usr/bin/env bash

set -euo pipefail

# @describe Flatten a PDF by removing annotations and re-rendering
# @arg input! Input PDF file
# @arg output Output PDF file (defaults to <input>.flat.pdf)

# Declare variables not to trip shellcheck.
declare argc_input argc_output
eval "$(argc --argc-eval "$0" "$@")"

if [[ ! -f "$argc_input" ]]; then
  echo "Error: File '$argc_input' does not exist" >&2
  exit 1
fi

# Determine output file: use argument or default to <basename>.flat.pdf
if [[ -n "${argc_output:-}" ]]; then
  output_file="$argc_output"
else
  # Remove .pdf extension if present, then add .flat.pdf
  base="${argc_input%.pdf}"
  output_file="${base}.flat.pdf"
fi

# https://unix.stackexchange.com/questions/162922
gs -dSAFER -dBATCH -dNOPAUSE -dNOCACHE -sDEVICE=pdfwrite \
  -sColorConversionStrategy=LeaveColorUnchanged \
  -dAutoFilterColorImages=true \
  -dAutoFilterGrayImages=true \
  -dDownsampleMonoImages=true \
  -dDownsampleGrayImages=true \
  -dDownsampleColorImages=true \
  -dPreserveAnnots=false \
  -sOutputFile="$output_file" "$argc_input"

echo "Flattened PDF written to: $output_file"
