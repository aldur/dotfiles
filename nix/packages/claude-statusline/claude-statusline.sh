#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
CTX_K=$((CTX_SIZE / 1000))k

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'; DIM='\033[2m'; RESET='\033[0m'

# Color-coded compact context bar
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR="${BAR}█"; done
for ((i=0; i<EMPTY; i++)); do BAR="${BAR}░"; done

# Git branch
BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
fi

# Repo name
REPO_NAME=""
REMOTE=$(git remote get-url origin 2>/dev/null || true)
if [ -n "$REMOTE" ]; then
    REPO_NAME=$(basename "${REMOTE%.git}")
fi

# Show last 2 path segments
DIR_SHORT=$(echo "$DIR" | awk -F/ '{if (NF>2) print $(NF-1)"/"$NF; else print $0}')
printf '%b' "${DIR_SHORT}"
[ -n "$BRANCH" ] && printf '%b' " ${GREEN}${BRANCH}${RESET}"
[ -n "$REPO_NAME" ] && printf '%b' " ${CYAN}${REPO_NAME}${RESET}"

# Cache hit ratio
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
INPUT=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
TOTAL_IN=$((CACHE_READ + CACHE_CREATE + INPUT))
if [ "$TOTAL_IN" -gt 0 ]; then
    CACHE_PCT=$((CACHE_READ * 100 / TOTAL_IN))
    CACHE_INFO=" ${DIM}cache:${RESET}${GREEN}${CACHE_PCT}%${RESET}"
else
    CACHE_INFO=""
fi

printf '%b' " | ${BAR_COLOR}${BAR}${RESET} ${PCT}%${CACHE_INFO} ${CYAN}[${MODEL} ${CTX_K}]${RESET}\n"
