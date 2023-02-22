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

file_path=$1
output=~/reMarkablePages/

echo "Processing" "$file_path"
/Users/aldur/Work/lines-are-rusty/target/release/lines-are-rusty "$file_path" -o "$file_path.svg"
# brew install librsvg
rsvg-convert -f pdf -o "$file_path.pdf" "$file_path.svg"
rm "$file_path.svg"
shortcuts run "Extract Text" -i "$file_path.pdf" >"$file_path.ocr.txt"

output="$output"/"$(date -ur "$file_path" "+%Y-%m-%d")"

notebook_metadata=$(dirname "$file_path").metadata
notebook=$(jq -r '.visibleName' <"$notebook_metadata")

output="$output"/"$notebook"
mkdir -p "$output"

mv "$file_path".{pdf,ocr.txt} "$output"
touch -r "$file_path" "$output"/"$(basename "$file_path")".{pdf,ocr.txt}
