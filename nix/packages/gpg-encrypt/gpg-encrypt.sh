#!/usr/bin/env bash

# shellcheck disable=SC2016
if test "$BASH" = "" || "$BASH" -uc 'a=();true "${a[@]}"' 2>/dev/null; then
	# Bash 4.4, Zsh
	set -Eeuo pipefail
else
	# Bash 4.3 and older chokes on empty arrays with set -u.
	set -Eeo pipefail
fi
if shopt | grep globstar &>/dev/null; then
	shopt -s nullglob globstar || true
fi

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
    ARG=$?
	trap - SIGINT SIGTERM ERR EXIT
    exit $ARG
}

if [ ! -z ${DEBUG+x} ]; then
	set -x
fi

# Function to show usage
usage() {
	cat <<EOF
Usage: $0 [OPTIONS] [FILE]

Encrypt data using GPG with recipient keys from your GPG keyring.

OPTIONS:
  --email EMAIL       Encrypt to all keys associated with this email address
                      Can also be set via GPG_ENCRYPT_EMAIL environment variable
                      If not specified, uses default email (when installed via Nix)
  --output FILE       Write output to FILE instead of default location
  -h, --help         Display this help and exit

BEHAVIOR:
  - If no FILE is provided, reads from stdin and outputs with --armor to stdout
  - If FILE is provided, writes to <filename>.gpg
  - If --output is specified, writes to the specified output file
  - When outputting to stdout and input exceeds 1KB, prompts for confirmation

EXAMPLES:
  # Encrypt stdin to stdout (using default email)
  echo "secret" | $0

  # Encrypt to specific email
  echo "secret" | $0 --email user@example.com

  # Encrypt a file
  $0 --email user@example.com document.txt

EOF
	exit 0
}

# Parse arguments
EMAIL="${GPG_ENCRYPT_EMAIL:-}"
OUTPUT_FILE=""
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
	case $1 in
		--email)
			EMAIL="$2"
			shift 2
			;;
		--output)
			OUTPUT_FILE="$2"
			shift 2
			;;
		-h|--help)
			usage
			;;
		-*)
			echo "Error: Unknown option $1"
			usage
			;;
		*)
			if [ -z "$INPUT_FILE" ]; then
				INPUT_FILE="$1"
			else
				echo "Error: Multiple input files specified"
				exit 1
			fi
			shift
			;;
	esac
done

# Determine recipients from email
# Fall back to default email if not specified
if [ -z "$EMAIL" ]; then
	EMAIL="${GPG_ENCRYPT_DEFAULT_EMAIL:-}"
fi

if [ -z "$EMAIL" ]; then
	echo "Error: No encryption recipient email specified."
	echo "Use --email option or set GPG_ENCRYPT_EMAIL/GPG_ENCRYPT_DEFAULT_EMAIL environment variable."
	exit 1
fi

# Get all primary key fingerprints (only 'pub' keys, not 'sub' keys) for the email
RECIPIENTS=()
PREV_LINE=""
while IFS= read -r line; do
	TYPE=$(echo "$line" | cut -d: -f1)

	if [[ "$TYPE" == "pub" ]]; then
		PREV_LINE="$line"
	elif [[ "$TYPE" == "fpr" ]] && [[ -n "$PREV_LINE" ]]; then
		# This fingerprint belongs to a primary key
		FPR=$(echo "$line" | cut -d: -f10)
		[[ -n "$FPR" ]] && RECIPIENTS+=("$FPR")
		PREV_LINE=""
	elif [[ "$TYPE" == "sub" ]]; then
		# Reset if we hit a subkey - we don't want subkey fingerprints
		PREV_LINE=""
	fi
done < <(gpg --batch --with-colons --list-keys "$EMAIL" 2>/dev/null)

if [ ${#RECIPIENTS[@]} -eq 0 ]; then
	echo "Error: No primary keys found in GPG keyring for email '$EMAIL'."
	echo "Make sure the keys are imported with: gpg --import <keyfile>"
	exit 1
fi

# Build GPG recipient arguments
GPG_ARGS=(--batch --yes --trust-model always)
for recipient in "${RECIPIENTS[@]}"; do
	GPG_ARGS+=(--recipient "$recipient")
done

# Determine input source and output destination
if [ -z "$INPUT_FILE" ]; then
	# Reading from stdin
	if [ -z "$OUTPUT_FILE" ]; then
		# Output to stdout with armor
		# First, read stdin into a temp file to check size
		TEMP_INPUT=$(mktemp)
		trap "rm -f $TEMP_INPUT; cleanup" SIGINT SIGTERM ERR EXIT
		cat > "$TEMP_INPUT"

		INPUT_SIZE=$(stat -c%s "$TEMP_INPUT" 2>/dev/null || stat -f%z "$TEMP_INPUT" 2>/dev/null || echo 0)

		# Check if size exceeds 1KB (1024 bytes)
		if [ "$INPUT_SIZE" -gt 1024 ]; then
			echo "Warning: Input size is $INPUT_SIZE bytes (> 1KB)." >&2
			echo "Are you sure you want to output to stdout? [y/N]" >&2
			read -r response
			if [[ ! "$response" =~ ^[Yy]$ ]]; then
				echo "Aborted." >&2
				rm -f "$TEMP_INPUT"
				exit 1
			fi
		fi

		gpg --encrypt --armor "${GPG_ARGS[@]}" < "$TEMP_INPUT"
		rm -f "$TEMP_INPUT"
	else
		# Output to specified file
		gpg --encrypt --output "$OUTPUT_FILE" "${GPG_ARGS[@]}"
	fi
else
	# Reading from file
	if [ ! -f "$INPUT_FILE" ]; then
		echo "Error: Input file '$INPUT_FILE' not found."
		exit 1
	fi

	if [ -z "$OUTPUT_FILE" ]; then
		# Default output: <filename>.gpg
		OUTPUT_FILE="${INPUT_FILE}.gpg"
	fi

	gpg --encrypt --output "$OUTPUT_FILE" "${GPG_ARGS[@]}" "$INPUT_FILE"
	echo "Encrypted file written to: $OUTPUT_FILE"
fi
