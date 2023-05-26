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

# Requires:
# $ brew install librsvg qpdf
# lines-are-rusty (with your patch)
# remarks (https://github.com/lucasrla/remarks)
# Bash having full-disk-access (if running through launchd)

# set -x # DEBUG, print failing command

input_file_path=$1
output=/Users/aldur/Documents/reMarkablePages/

export PATH="$PATH:/opt/homebrew/bin/"

# Echoes to both STDOUT and STDERR
echo "$(date -Iseconds)" - "$$" - "$PPID" - Processing "$input_file_path"... | tee /dev/stderr

if [[ $input_file_path == *"/.stversions/"* ]]; then
	echo "Skipping '.stsversions' file $input_file_path..."
	exit 0
fi

container_dir=$(dirname "$input_file_path")
container_metadata="$container_dir".metadata
container_name=$(jq -r '.visibleName' <"$container_metadata")
container_name="${container_name//\//}" # Strip slashes in container name

output="$output"/"$(date -ur "$input_file_path" "+%Y-%m-%d")"
output="$output"/"$container_name"
mkdir -p "$output"

# We use this as a base not to create files within the original directory.
full_output_no_ext="$output"/"$(basename "$input_file_path")"

/Users/aldur/Work/lines-are-rusty/target/release/lines-are-rusty "$input_file_path" -o "$full_output_no_ext.svg"
rsvg-convert -f pdf -o "$full_output_no_ext.pdf" "$full_output_no_ext.svg"
rm "$full_output_no_ext.svg"

page_uuid=$(basename "$input_file_path" .rm) # Get page UUID without `.rm` extension

# OCR
mkdir -p "$output"/"ocr"
ocr_output="$output"/"ocr"/$(basename "$input_file_path").ocr.txt
shortcuts run "Extract Text" -i "$full_output_no_ext.pdf" >"$ocr_output"
touch -r "$input_file_path" "$ocr_output"
# Add to PDF as attachment/embedded file.
qpdf "$full_output_no_ext.pdf" --add-attachment "$ocr_output" --mimetype=text/plain --description="OCR, Apple Handwriting Recognition" -- --replace-input

container_content="$container_dir".content

# This is the index of the page within the document.
# Can fail and return -1, e.g. if the page has been since deleted
# (this happens while processing an old `.rm` file when the corresponding
# `json` has been updated).
page_index=$(jq '(.pages | index("'"$page_uuid"'") // -2) + 1' "$container_content")
if [[ $page_index -lt 0 ]]; then
	echo >&2 "Warning: Processing page that doesn't have a corresponding page index."
	echo >&2 "Warning [cont'd]: Input file path: ${input_file_path}."
	echo >&2 "Warning [cont'd]: .content file:"
	jq -c '.' "${container_content}" >&2
fi

# If this is != -1, then we have extracted `lines` from a page that was
# originally in a PDF file.
pdf_page_index=$(jq '(.pageIndex = (.pages | index("'"$page_uuid"'")) | (if has("redirectionPageMap") then .redirectionPageMap[.pageIndex] else null end) // -2) + 1' "$container_content")
pdf_file="${container_dir}".pdf

if [[ -f $pdf_file ]] && [[ $pdf_page_index -lt 0 ]]; then
	echo >&2 "Warning: Processing a PDF page that doesn't have a corresponding index in the PDF file."
	echo >&2 "Warning [cont'd]: Input file path: ${input_file_path}."
	echo >&2 "Warning [cont'd]: PDF file path: ${pdf_file}."
	echo >&2 "Warning [cont'd]: .content file:"
	jq -c '.' "${container_content}" >&2
fi

container_uuid=$(basename "$container_dir")
full_output_with_page="$output"/"$page_index"."$container_uuid"."$page_uuid"
full_container="$output"/../"$container_name".pdf

if [[ -f $pdf_file ]] && [[ $page_index -gt 0 ]] && [[ $pdf_page_index -gt 0 ]]; then
	# Remarks leaves a few folder mimicing the file hierarchy of the file.
	# We use a temporary directory to not having to find the proper path.
	# Then we remove it, as we don't need anything else from it.
	remarks_output_dir=$(mktemp -d -t remarks-XXXXXXXXXX)

	PIPENV_PIPFILE=/Users/aldur/Work/remarks/Pipfile pipenv run python -m \
		remarks "$(dirname "${container_dir}")" "${remarks_output_dir}" --file_uuid "${container_uuid}" \
		--per_page_targets pdf --log_level WARNING

	find "${remarks_output_dir}" -iname "*${container_name} _highlights.md" -exec mv {} "${output}/../${container_name}.md" \;
	find "${remarks_output_dir}" -iname "*${container_name} _remarks.pdf" -exec mv {} "${full_container}" \;

	# Extract the specific page from the PDF.
	qpdf "${full_container}" --pages . "$pdf_page_index" -- "$full_output_with_page".pdf

	rm -r "${remarks_output_dir}"

	# We also discard the PDF we generated from the annotations. That was only useful to `ocr` it.
	rm "$full_output_no_ext.pdf"
else
	mv "$full_output_no_ext.pdf" "$full_output_with_page".pdf
	qpdf --empty --pages "$output"/*."$container_uuid".*.pdf -- "$full_container"
fi

ocr_output_with_page="$output"/"ocr"/"$page_index"."$container_uuid"."$page_uuid".ocr.txt
mv "$ocr_output" "$ocr_output_with_page"
touch -r "$input_file_path" "$full_output_with_page".pdf
touch -r "$input_file_path" "$ocr_output_with_page"

# TODO: Add attachments / OCRs to merged PDF.
