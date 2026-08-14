#!/usr/bin/env bash

set -euo pipefail

# @describe Strip leading and trailing whitespace from each line of stdin

eval "$(argc --argc-eval "$0" "$@")"

sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
