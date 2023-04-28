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

# brew install librsvg qpdf

input_file_path=$1
output=/Users/aldur/Documents/reMarkablePages/

export PATH="$PATH:/opt/homebrew/bin/"

# Echoes to both STDOUT and STDERR
echo "$(date -Iseconds)" - "$$" - "$PPID" - Processing "$input_file_path"... | tee /dev/stderr

if [[ $input_file_path == *"/.stversions/"* ]]; then
	echo "Skipping '.stsversions' file $input_file_path..."
	exit 0
fi

notebook_file=$(dirname "$input_file_path")
notebook_metadata="$notebook_file".metadata
notebook_name=$(jq -r '.visibleName' <"$notebook_metadata")
notebook_name="${notebook_name//\//}" # Strip slashes in notebook name

output="$output"/"$(date -ur "$input_file_path" "+%Y-%m-%d")"
output="$output"/"$notebook_name"
mkdir -p "$output"

# We use this as a base not to create files within the original directory.
full_output_no_ext="$output"/"$(basename "$input_file_path")"

/Users/aldur/Work/lines-are-rusty/target/release/lines-are-rusty "$input_file_path" -o "$full_output_no_ext.svg"
rsvg-convert -f pdf -o "$full_output_no_ext.pdf" "$full_output_no_ext.svg"
rm "$full_output_no_ext.svg"

page_uid=$(basename "$input_file_path" .rm) # Get page UUID without `.rm` extension

# OCR
mkdir -p "$output"/"ocr"
ocr_output="$output"/"ocr"/$(basename "$input_file_path").ocr.txt
shortcuts run "Extract Text" -i "$full_output_no_ext.pdf" >"$ocr_output"
touch -r "$input_file_path" "$ocr_output"
# Add to PDF as attachment/embedded file.
qpdf "$full_output_no_ext.pdf" --add-attachment "$ocr_output" --mimetype=text/plain --description="OCR, Apple Handwriting Recognition" -- --replace-input

notebook_content="$notebook_file".content

# If it's a PDF, redirect the page to the actual page (in case of addition, deletion).
# Otherwise, get the page index.
# If not found, fallback to -1.
page_index=$(jq '(.pages | index("'"$page_uid"'") // -2) + 1' "$notebook_content")
pdf_page_index=$(jq '(.pageIndex = (.pages | index("'"$page_uid"'")) | (if has("redirectionPageMap") then .redirectionPageMap[.pageIndex] else null end) // -2) + 1' "$notebook_content")

notebook_uid=$(basename "$notebook_file")
full_output_with_page="$output"/"$page_index"."$notebook_uid"."$page_uid"

pdf_file="$notebook_file".pdf
if [[ -f $pdf_file ]] && [[ $page_index -gt 0 ]] && [[ $pdf_page_index -gt 0 ]]; then
	qpdf --empty --pages "$pdf_file" "$pdf_page_index" -- "$full_output_with_page".pdf
	qpdf --replace-input --overlay "$full_output_no_ext".pdf -- "$full_output_with_page".pdf
	rm "$full_output_no_ext.pdf"
else
	mv "$full_output_no_ext.pdf" "$full_output_with_page".pdf
fi

ocr_output_with_page="$output"/"ocr"/"$page_index"."$notebook_uid"."$page_uid".ocr.txt
mv "$ocr_output" "$ocr_output_with_page"
touch -r "$input_file_path" "$full_output_with_page".pdf
touch -r "$input_file_path" "$ocr_output_with_page"

full_notebook="$output"/../"$notebook_name".pdf
qpdf --empty --pages "$output"/*."$notebook_uid".*.pdf -- "$full_notebook"
# TODO: Add attachments / OCRs to merged PDF.
