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

Encrypt data using GPG with a set of recipient keys loaded from a file.

OPTIONS:
  --keys-file FILE    File containing GPG key IDs/emails (one per line)
                      Can also be set via GPG_KEYS_FILE environment variable
                      If not specified, uses default keys (when installed via Nix)
  --output FILE       Write output to FILE instead of default location
  -h, --help         Display this help and exit

BEHAVIOR:
  - If no FILE is provided, reads from stdin and outputs with --armor to stdout
  - If FILE is provided, writes to <filename>.gpg
  - If --output is specified, writes to the specified output file
  - When outputting to stdout and input exceeds 1KB, prompts for confirmation

EXAMPLES:
  # Encrypt stdin to stdout
  echo "secret" | $0 --keys-file keys.txt

  # Encrypt a file
  $0 --keys-file keys.txt document.txt

  # Encrypt with custom output
  $0 --keys-file keys.txt --output encrypted.gpg document.txt

EOF
	exit 0
}

# Parse arguments
KEYS_FILE="${GPG_KEYS_FILE:-}"
OUTPUT_FILE=""
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
	case $1 in
		--keys-file)
			KEYS_FILE="$2"
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

# Validate keys file
# Fall back to default keys file if available (set by Nix wrapper)
if [ -z "$KEYS_FILE" ]; then
	if [ -n "${GPG_ENCRYPT_DEFAULT_KEYS:-}" ] && [ -f "$GPG_ENCRYPT_DEFAULT_KEYS" ]; then
		KEYS_FILE="$GPG_ENCRYPT_DEFAULT_KEYS"
	else
		echo "Error: Keys file not specified. Use --keys-file option or set GPG_KEYS_FILE environment variable."
		exit 1
	fi
fi

if [ ! -f "$KEYS_FILE" ]; then
	echo "Error: Keys file '$KEYS_FILE' not found."
	exit 1
fi

# Read keys from file (skip empty lines and comments)
RECIPIENTS=()
while IFS= read -r line; do
	# Skip empty lines and comments
	[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
	RECIPIENTS+=("$line")
done < "$KEYS_FILE"

if [ ${#RECIPIENTS[@]} -eq 0 ]; then
	echo "Error: No valid recipient keys found in '$KEYS_FILE'."
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
