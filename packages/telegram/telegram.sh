#!/usr/bin/env bash

set -euo pipefail

# @describe Send a message, photo or video with a Telegram bot
# @option -c --chat-id ID of the Telegram chat to send the message to (defaults to the CHAT_ID environment variable)
# @option -t --bot-token Your Telegram bot token (prefer the BOT_TOKEN environment variable: an option shows the token in the process list)
# @option -p --photo Send the picture at this path, with the message as its caption
# @option -v --video Send the video at this path, with the message as its caption
# @arg message! The text to send

declare argc_chat_id argc_bot_token argc_photo argc_video argc_message
eval "$(argc --argc-eval "$0" "$@")"

if [ -n "${DEBUG+x}" ]; then
	set -x
fi

CHAT_ID="${argc_chat_id:-${CHAT_ID:-}}"
BOT_TOKEN="${argc_bot_token:-${BOT_TOKEN:-}}"

if [ -z "$CHAT_ID" ]; then
	echo "Error: CHAT_ID cannot be empty. Use '--chat-id' to set it."
	exit 1
fi

if [ -z "$BOT_TOKEN" ]; then
	echo "Error: BOT_TOKEN cannot be empty. Use '--bot-token' to set it."
	exit 1
fi

# The token goes into a curl config file below. A quote or a line break
# in the token would inject more config lines. Accept only the Telegram
# token format.
if ! [[ "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
	echo "Error: BOT_TOKEN does not match the Telegram token format (digits:base64url)."
	exit 1
fi

if [ -n "${argc_photo:-}" ] && [ -n "${argc_video:-}" ]; then
	echo "Error: --photo and --video exclude each other."
	exit 1
fi

MESSAGE="$argc_message"

# curl's -F syntax needs `"` and `\` escaped inside its own quoting when the
# value is a filename (an unquoted `@path` stops at `;` or `,`).
curl_f_escape() {
	printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

# --form-string (not -F) for user-supplied text: -F would expand a leading
# `@` or `<` into a file upload.
CURL_ARGS=(-q -s -S -L -o- --form-string "chat_id=${CHAT_ID}")

if [ -n "${argc_photo:-}" ]; then
	CURL_ARGS+=(--form-string "caption=${MESSAGE}")
	CURL_ARGS+=(-F "photo=@\"$(curl_f_escape "$argc_photo")\"")
	ENDPOINT="sendPhoto"
elif [ -n "${argc_video:-}" ]; then
	CURL_ARGS+=(--form-string "caption=${MESSAGE}")
	CURL_ARGS+=(-F "video=@\"$(curl_f_escape "$argc_video")\"")
	ENDPOINT="sendVideo"
else
	CURL_ARGS+=(--form-string "text=${MESSAGE}")
	ENDPOINT="sendMessage"
fi

# The URL embeds the bot token; pass it via a config file on stdin so it
# never appears in the process list.
printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$BOT_TOKEN" "$ENDPOINT" \
	| curl "${CURL_ARGS[@]}" --config -
