#!/usr/bin/env bash

set -euo pipefail

# @describe Strip leading whitespace from each line of stdin

eval "$(argc --argc-eval "$0" "$@")"

sed 's/^[[:space:]]*//'
