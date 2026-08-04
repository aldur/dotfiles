#!/usr/bin/env bash

set -euo pipefail

# @describe Decode a TOTP setup QR code into its parameters
# @arg image! Path to the QR code image (png/jpg/etc.)
# @flag --raw Print the otpauth URI only

# Declare variables not to trip shellcheck.
declare argc_image argc_raw
eval "$(argc --argc-eval "$0" "$@")"

if [[ ! -f "$argc_image" ]]; then
  echo "Could not read image: $argc_image" >&2
  exit 1
fi

if ! uri=$(qrtool decode "$argc_image"); then
  echo "No QR code found in $argc_image" >&2
  exit 1
fi

if [[ "${argc_raw:-0}" == 1 ]]; then
  echo "$uri"
  exit 0
fi

if [[ "$uri" != otpauth://* ]]; then
  echo "Not an otpauth URI: $uri" >&2
  exit 1
fi

urldecode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

# otpauth://TYPE/LABEL?PARAMS — the label is ISSUER:ACCOUNT, URL-encoded.
rest="${uri#otpauth://}"
type="${rest%%/*}"
rest="${rest#*/}"
label="$rest"
query=""
if [[ "$rest" == *\?* ]]; then
  label="${rest%%\?*}"
  query="${rest#*\?}"
fi
label="$(urldecode "$label")"

issuer_label=""
account="$label"
if [[ "$label" == *:* ]]; then
  issuer_label="${label%%:*}"
  account="${label#*:}"
fi

declare -A params=()
IFS='&' read -ra pairs <<<"$query"
for pair in "${pairs[@]}"; do
  [[ "$pair" == *=* ]] || continue
  params["${pair%%=*}"]="$(urldecode "${pair#*=}")"
done

print_kv() {
  if [[ -n "$2" ]]; then
    printf '%-9s  %s\n' "$1" "$2"
  fi
}

print_kv type "$type"
print_kv issuer "${params[issuer]:-$issuer_label}"
print_kv account "$account"
print_kv secret "${params[secret]:-}"
print_kv algorithm "${params[algorithm]:-SHA1}"
print_kv digits "${params[digits]:-6}"
print_kv period "${params[period]:-30}"
print_kv counter "${params[counter]:-}"

printf '\nuri: %s\n' "$uri"
