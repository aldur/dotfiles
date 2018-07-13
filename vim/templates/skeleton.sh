#!/usr/bin/env bash

# shellcheck disable=SC2016
if test "$BASH" = "" || "$BASH" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
    # Bash 4.4, Zsh
    set -euo pipefail
else
    # Bash 4.3 and older chokes on empty arrays with set -u.
    set -eo pipefail
fi
shopt -s nullglob globstar

finish() {
    true
}
trap finish EXIT
