#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: flatten-pdf <input.pdf> [output.pdf]" >&2
  exit 1
fi

input_file="$1"

if [[ ! -f "$input_file" ]]; then
  echo "Error: File '$input_file' does not exist" >&2
  exit 1
fi

# Determine output file: use second argument or default to <basename>.flat.pdf
if [[ $# -ge 2 ]]; then
  output_file="$2"
else
  # Remove .pdf extension if present, then add .flat.pdf
  base="${input_file%.pdf}"
  output_file="${base}.flat.pdf"
fi

# https://unix.stackexchange.com/questions/162922
gs -dSAFER -dBATCH -dNOPAUSE -dNOCACHE -sDEVICE=pdfwrite \
  -sColorConversionStrategy=/LeaveColorUnchanged \
  -dAutoFilterColorImages=true \
  -dAutoFilterGrayImages=true \
  -dDownsampleMonoImages=true \
  -dDownsampleGrayImages=true \
  -dDownsampleColorImages=true \
  -dPreserveAnnots=false \
  -sOutputFile="$output_file" "$input_file"

echo "Flattened PDF written to: $output_file"
