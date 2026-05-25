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

while getopts ":c:t:h:p:v:" opt; do
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
	echo "Error: CHAT_ID cannot be empty. Use '-c' or '--chat-id' to set it."
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
CURL_OPTIONS="-q -s -S -L -o-"

CURL_CMD_STR="curl ${CURL_OPTIONS} "
CURL_CMD_STR+="-F chat_id=${CHAT_ID} "

case $TYPE in
	m)
        CURL_CMD_STR+="-F text=\"${MESSAGE}\" "
		ENDPOINT="sendMessage"
		;;
	p)
        CURL_CMD_STR+="-F caption=\"${MESSAGE}\" "
		CURL_CMD_STR+="-F photo=@\"${FILE_TO_SEND}\" "
		ENDPOINT="sendPhoto"
		;;
	v)
        CURL_CMD_STR+="-F caption=\"${MESSAGE}\" "
		CURL_CMD_STR+="-F video=@\"${FILE_TO_SEND}\" "
		ENDPOINT="sendVideo"
		;;
	\?)
		echo "Invalid type: $type!"
		exit 1
		;;
esac

CURL_CMD_STR+="https://api.telegram.org/bot${BOT_TOKEN}/${ENDPOINT}"

eval $CURL_CMD_STR
exit $?
