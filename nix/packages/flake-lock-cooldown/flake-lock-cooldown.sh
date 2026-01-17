#!/usr/bin/env bash
set -euo pipefail

# @describe Update a flake input to a commit from at least N time ago
# @option -t --time <TIME> How long ago (e.g., '2 weeks', '3 days') [default: `1 week`]
# @arg input! Flake input name to update
# @arg flake-path Path to flake directory [default: .]

declare argc_time argc_input argc_flake_path
eval "$(argc --argc-eval "$0" "$@")"

TIME_AGO="${argc_time:-1 week} ago"
INPUT_NAME="$argc_input"
FLAKE_PATH="${argc_flake_path:-.}"
LOCK_FILE="$FLAKE_PATH/flake.lock"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "Error: $LOCK_FILE not found" >&2
  exit 1
fi

# Parse owner/repo from flake.lock
NODE_INFO=$(jq -r --arg input "$INPUT_NAME" '.nodes[$input].locked // empty' "$LOCK_FILE")

if [[ -z "$NODE_INFO" ]]; then
  echo "Error: Input '$INPUT_NAME' not found in flake.lock" >&2
  exit 1
fi

TYPE=$(echo "$NODE_INFO" | jq -r '.type')

if [[ "$TYPE" != "github" ]]; then
  echo "Error: Input '$INPUT_NAME' is not a GitHub source (type: $TYPE)" >&2
  exit 1
fi

OWNER=$(echo "$NODE_INFO" | jq -r '.owner')
REPO=$(echo "$NODE_INFO" | jq -r '.repo')

echo "Found input: github:$OWNER/$REPO" >&2

# Fetch most recent commit at least $TIME_AGO old
# NOTE: This requires GNU coreutils `date`
UNTIL_DATE=$(date -u -d "$TIME_AGO" +%Y-%m-%dT%H:%M:%SZ)

API_URL="https://api.github.com/repos/$OWNER/$REPO/commits?until=$UNTIL_DATE&per_page=1"
RESPONSE=$(curl --no-verbose -s "$API_URL")

COMMIT=$(echo "$RESPONSE" | jq -r '.[0].sha // empty')

if [[ -z "$COMMIT" ]]; then
  echo "Error: No commits found older than $TIME_AGO" >&2
  exit 1
fi

COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date')
COMMIT_MSG=$(echo "$RESPONSE" | jq -r '.[0].commit.message | split("\n")[0]')
COMMIT_URL="https://github.com/$OWNER/$REPO/commit/$COMMIT"
COMMIT_LINK=$'\e]8;;'"$COMMIT_URL"$'\e\\'"$COMMIT"$'\e]8;;\e\\'

echo "Found commit: $COMMIT_LINK" >&2
echo "Date: $COMMIT_DATE" >&2
echo "Message: $COMMIT_MSG" >&2
echo ""

CMD="nix flake update $INPUT_NAME --override-input $INPUT_NAME github:$OWNER/$REPO/$COMMIT"
echo "Will run: '$CMD'" >&2
read -rp "Press Enter to continue (Ctrl-C to cancel): " >&2

$CMD
