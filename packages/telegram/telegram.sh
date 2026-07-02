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

# Set defaults
CHAT_ID="${CHAT_ID:-}"
BOT_TOKEN="${BOT_TOKEN:-}"

TYPE='m'
FILE_TO_SEND=""

while getopts ":c:t:p:v:h" opt; do
	case $opt in
		c) CHAT_ID="$OPTARG" ;;
		t) BOT_TOKEN="$OPTARG" ;;
		p|v)
			FILE_TO_SEND="$OPTARG"
			TYPE=$opt
			;;
		h)
			echo "Usage: $0 [options] <message>"
			echo "Options:"
			echo "  -c, ID of the Telegram chat to send the message to"
			echo "  -t, Your Telegram Bot Token"
			echo "  -v, Send video at path"
			echo "  -p, Send picture at path"
			echo "  -h, Display this help and exit"
			exit 0
			;;
		\?)
			echo "Invalid option: -$OPTARG. Use '-h' for help."
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument"
			exit 1
			;;
	esac
done

# Shift to access positional args (message in this case)
shift $((OPTIND - 1))

if [ -z "$CHAT_ID" ]; then
	echo "Error: CHAT_ID cannot be empty. Use '-c' to set it."
	exit 1
fi

if [ -z "$BOT_TOKEN" ]; then
	echo "Error: BOT_TOKEN cannot be empty. Use '-t' to set it."
	exit 1
fi

# Check if message is provided as a mandatory parameter
if [ $# -eq 0 ]; then
	echo "Error: Message is a required parameter"
	exit 1
fi

MESSAGE="$1"

# curl's -F syntax needs `"` and `\` escaped inside its own quoting when the
# value is a filename (an unquoted `@path` stops at `;` or `,`).
curl_f_escape() {
	printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

# --form-string (not -F) for user-supplied text: -F would expand a leading
# `@` or `<` into a file upload.
CURL_ARGS=(-q -s -S -L -o- --form-string "chat_id=${CHAT_ID}")

case $TYPE in
	m)
		CURL_ARGS+=(--form-string "text=${MESSAGE}")
		ENDPOINT="sendMessage"
		;;
	p)
		CURL_ARGS+=(--form-string "caption=${MESSAGE}")
		CURL_ARGS+=(-F "photo=@\"$(curl_f_escape "$FILE_TO_SEND")\"")
		ENDPOINT="sendPhoto"
		;;
	v)
		CURL_ARGS+=(--form-string "caption=${MESSAGE}")
		CURL_ARGS+=(-F "video=@\"$(curl_f_escape "$FILE_TO_SEND")\"")
		ENDPOINT="sendVideo"
		;;
	*)
		echo "Invalid type: $TYPE!"
		exit 1
		;;
esac

# The URL embeds the bot token; pass it via a config file on stdin so it
# never appears in the process list.
printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$BOT_TOKEN" "$ENDPOINT" \
	| curl "${CURL_ARGS[@]}" --config -
