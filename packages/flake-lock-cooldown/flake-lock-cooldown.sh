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

# Input names need not match node names; follows references start at the root.
node_info() {
  jq -c --arg input "$INPUT_NAME" '
    . as $lock |
    def resolve($ref):
      if ($ref | type) == "array" then
        reduce $ref[] as $name ($lock.root; resolve($lock.nodes[.].inputs[$name]))
      else $ref end;
    resolve($input | split("/")) as $node |
    if $node == null then empty else $lock.nodes[$node] + {nodeId: $node} end
  ' "$LOCK_FILE"
}
NODE_INFO=$(node_info)

if [[ -z "$NODE_INFO" ]]; then
  echo "Error: Input '$INPUT_NAME' not found in flake.lock" >&2
  exit 1
fi

TYPE=$(echo "$NODE_INFO" | jq -r '.locked.type')

if [[ "$TYPE" != "github" ]]; then
  echo "Error: Input '$INPUT_NAME' is not a GitHub source (type: $TYPE)" >&2
  exit 1
fi

OWNER=$(echo "$NODE_INFO" | jq -r '.locked.owner')
REPO=$(echo "$NODE_INFO" | jq -r '.locked.repo')
REF=$(echo "$NODE_INFO" | jq -r '.original.ref // .original.rev // empty')
ORIGINAL=$(echo "$NODE_INFO" | jq -c '.original')
INPUT_DIR=$(echo "$NODE_INFO" | jq -r '.original.dir // .locked.dir // empty')

echo "Found input: github:$OWNER/$REPO" >&2

# Fetch most recent commit at least $TIME_AGO old
# NOTE: This requires GNU coreutils `date`
UNTIL_DATE=$(date -u -d "$TIME_AGO" +%Y-%m-%dT%H:%M:%SZ)

API_URL="https://api.github.com/repos/$OWNER/$REPO/commits"
QUERY=(--data-urlencode "until=$UNTIL_DATE" --data-urlencode "per_page=1")
if [[ -n "$REF" ]]; then
  QUERY+=(--data-urlencode "sha=$REF")
fi
RESPONSE=$(curl --no-verbose -fsSL --get "${QUERY[@]}" "$API_URL")

COMMIT=$(echo "$RESPONSE" | jq -r '.[0].sha // empty')

if [[ -z "$COMMIT" ]]; then
  echo "Error: No commits found older than $TIME_AGO" >&2
  exit 1
fi

COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.[0].commit.committer.date')
# Remove the control characters: the message comes from a remote
# repository and goes to the terminal.
COMMIT_MSG=$(echo "$RESPONSE" | jq -r '.[0].commit.message | split("\n")[0]' | tr -d '[:cntrl:]')
COMMIT_URL="https://github.com/$OWNER/$REPO/commit/$COMMIT"
COMMIT_LINK=$'\e]8;;'"$COMMIT_URL"$'\e\\'"$COMMIT"$'\e]8;;\e\\'

echo "Found commit: $COMMIT_LINK" >&2
echo "Date: $COMMIT_DATE" >&2
echo "Message: $COMMIT_MSG" >&2
echo ""

OVERRIDE="github:$OWNER/$REPO/$COMMIT"
if [[ -n "$INPUT_DIR" ]]; then
  OVERRIDE+="?dir=$(printf '%s' "$INPUT_DIR" | jq -sRr @uri)"
fi
CMD=(nix flake update "$INPUT_NAME" --flake "$FLAKE_PATH" --override-input "$INPUT_NAME" "$OVERRIDE")
echo "Will run: ${CMD[*]}" >&2
read -rp "Press Enter to continue (Ctrl-C to cancel): " >&2

"${CMD[@]}"

# The override selects the locked revision, but must not replace the declared
# branch with that fixed revision for future cooldown updates.
NODE_ID=$(node_info | jq -r '.nodeId')
temporary=$(mktemp "${LOCK_FILE}.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
jq --arg node "$NODE_ID" --argjson original "$ORIGINAL" \
  '.nodes[$node].original = $original' "$LOCK_FILE" > "$temporary"
mv -f -- "$temporary" "$LOCK_FILE"
