#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <input-name> [flake-path]" >&2
  exit 1
fi

INPUT_NAME="$1"
FLAKE_PATH="${2:-.}"
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

echo "Found: github:$OWNER/$REPO" >&2

# Fetch most recent commit at least 1 week old
UNTIL_DATE=$(date -u -d '1 week ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1w +%Y-%m-%dT%H:%M:%SZ)
API_URL="https://api.github.com/repos/$OWNER/$REPO/commits?until=$UNTIL_DATE&per_page=1"

RESPONSE=$(curl -s "$API_URL")
COMMIT=$(echo "$RESPONSE" | jq -r '.[0].sha // empty')

if [[ -z "$COMMIT" ]]; then
  echo "Error: No commits found older than 1 week" >&2
  exit 1
fi

COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date')
COMMIT_MSG=$(echo "$RESPONSE" | jq -r '.[0].commit.message | split("\n")[0]')

echo "Found commit: $COMMIT" >&2
echo "Date: $COMMIT_DATE" >&2
echo "Message: $COMMIT_MSG" >&2
echo ""
echo "Run this command:"
echo "  nix flake update $INPUT_NAME --override-input $INPUT_NAME github:$OWNER/$REPO/$COMMIT"
