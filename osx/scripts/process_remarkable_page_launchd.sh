#!/usr/bin/env bash

# shellcheck disable=SC2016
if test "$BASH" = "" || "$BASH" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
	# Bash 4.4, Zsh
	set -Eeuo pipefail
else
	# Bash 4.3 and older chokes on empty arrays with set -u.
	set -Eeo pipefail
fi
if shopt | grep globstar; then
	shopt -s nullglob globstar || true
fi

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
}

echo "Executing 'process_remarkable_page_launchd.sh'..."

/opt/homebrew/bin/fswatch \
	--recursive \
	-0 \
	-e ".*" \
	-i "\\.rm$" \
	--event Created \
	--event Updated \
	--event Renamed \
	/Users/aldur/reMarkableRemote/ \
	| /usr/bin/xargs -t -0 -n 1 -I {} \
		/Users/aldur/.dotfiles/osx/scripts/process_remarkable_page.2.sh {}
