usage() {
    cat <<'EOF'
Usage: claude-log [--pretty] [--newest] [--turn N] [SESSION_FILE]

Interactively browse a Claude Code session transcript.

If SESSION_FILE is omitted, picks among sessions for the current
project (~/.claude/projects/<encoded-cwd>/*.jsonl), most recently
active first (ordered by last message timestamp, not file mtime).
Press ctrl-a in the session picker to broaden to all projects.

Options:
  --newest      Skip the picker; open the most recently active session in cwd.
  --turn N      Print the Nth user/assistant turn and exit (no turn picker).
                Negative N counts from the end (-1 = latest).
  --pretty      Render output via glow/bat if stdout is a TTY.
  -h, --help    Show this help and exit.
EOF
}

# Hidden subcommand: render the Nth JSONL line of FILE as a human turn.
# Used by the fzf preview and the final print.
render_record() {
    local n="$1" file="$2"
    case "$n" in
        ''|*[!0-9]*) echo "claude-log: --_render needs a line number, got: '$n'" >&2; return 2 ;;
    esac
    sed -n "${n}p" "$file" | jq -r '
        if .type == "assistant" then
            (.message.content // []) | map(
                if   .type == "text"     then .text
                elif .type == "thinking" then "── thinking ──\n" + (.thinking // "")
                elif .type == "tool_use" then "── tool_use: " + .name + " ──\n" + (.input | tojson)
                else "" end
            ) | map(select(. != "")) | join("\n\n")
        elif .type == "user" then
            if (.message.content | type) == "string" then
                .message.content
            else
                (.message.content | map(
                    if .type == "tool_result" then
                        "── tool_result ──\n" +
                        (if (.content | type) == "string" then .content
                         else (.content | map(.text // (. | tojson)) | join("\n")) end)
                    else "" end
                ) | map(select(. != "")) | join("\n\n"))
            end
        else empty end'
}

print_header() {
    local file="$1" line_no="$2"
    local uuid title when
    uuid=$(basename "$file" .jsonl)
    # ai-title records get added/updated over time; the last one is current.
    title=$(jq -r 'select(.type=="ai-title") | .aiTitle' "$file" 2>/dev/null | tail -1)
    when=$(sed -n "${line_no}p" "$file" | jq -r '.timestamp // empty')
    [ -n "$when" ] && when=$(date -d "$when" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s' "$when")
    printf 'session: %s\n' "$uuid"
    [ -n "$title" ] && printf 'title:   %s\n' "$title"
    [ -n "$when" ]  && printf 'when:    %s\n' "$when"
    printf '──────────────────────────────────────────────────────────────\n'
}

summarize_session() {
    local file="$1"
    jq -r '
        select((.type == "user" and (.message.content | type) == "string") or
               (.type == "assistant" and ((.message.content // []) | any(.type == "text")))) |
        if .type == "user" then
            "[1;33m─── user ─────────────────────────────────────────────────────[0m\n" + .message.content
        else
            "[1;36m─── assistant ────────────────────────────────────────────────[0m\n" +
            ((.message.content // []) | map(select(.type == "text") | .text) | join("\n\n"))
        end
    ' "$file"
}

PROJECT_DIR="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr '/.' '-')"
self="$0"

# Emit one fzf row per session:  <colored display>\t<path>\t<corpus>
#   scope=project → just the current project's sessions
#   scope=all     → every session under ~/.claude/projects, prefixed with [project]
list_sessions() {
    local scope="$1" root maxdepth
    if [ "$scope" = "all" ]; then
        root="$HOME/.claude/projects"
        maxdepth=2
    else
        root="$PROJECT_DIR"
        maxdepth=1
    fi
    [ -d "$root" ] || return 0
    # Two-pass: prefix each row with the last-message epoch as a sort key,
    # then sort descending and strip the key. Falls back to file mtime if the
    # session has no .timestamp fields (older Claude Code versions).
    find "$root" -mindepth 1 -maxdepth "$maxdepth" -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null \
        | while IFS=$'\t' read -r mtime path; do
              actual_ts=$(tail -n 50 "$path" 2>/dev/null | jq -r 'select(.timestamp) | .timestamp' 2>/dev/null | tail -1)
              if [ -n "$actual_ts" ] && sort_key=$(date -d "$actual_ts" +%s 2>/dev/null); then
                  when=$(date -d "$actual_ts" '+%Y-%m-%d %H:%M')
              else
                  sort_key="${mtime%.*}"
                  when=$(date -d "@${sort_key}" '+%Y-%m-%d %H:%M')
              fi
              title=$(jq -r 'select(.type=="ai-title") | .aiTitle' "$path" 2>/dev/null | tail -1)
              if [ -n "$title" ]; then
                  label="$title"
              else
                  label=$(jq -r 'select(.type=="user" and (.message.content | type)=="string") | .message.content' "$path" 2>/dev/null \
                          | head -1)
              fi
              label=$(printf '%s' "$label" | tr '\n\r\t' '   ' | cut -c1-100)
              corpus=$(jq -r '
                  select((.type == "user" and (.message.content | type) == "string") or
                         (.type == "assistant" and ((.message.content // []) | any(.type == "text")))) |
                  if .type == "user" then .message.content
                  else (.message.content | map(select(.type == "text") | .text) | join(" "))
                  end' "$path" 2>/dev/null | tr '\n\r\t\000' '    ')
              if [ "$scope" = "all" ]; then
                  project=$(basename "$(dirname "$path")")
                  printf '%s\t\033[36m%s\033[0m  \033[2m[%s]\033[0m %s\t%s\t%s\n' "$sort_key" "$when" "$project" "$label" "$path" "$corpus"
              else
                  printf '%s\t\033[36m%s\033[0m  %s\t%s\t%s\n' "$sort_key" "$when" "$label" "$path" "$corpus"
              fi
          done \
        | sort -rn -t $'\t' -k1,1 \
        | cut -f2-
}

newest_in_project() {
    # Reuse list_sessions so we get the message-timestamp ordering, not mtime.
    list_sessions project | head -1 | cut -f2
}

# Translate a 1-based turn index (negative = from end) into the JSONL line
# number of the matching user/assistant record.
nth_turn_line() {
    local file="$1" n="$2" lines total
    lines=$(jq -r 'select(.type=="user" or .type=="assistant") | input_line_number' "$file" 2>/dev/null)
    [ -n "$lines" ] || { echo "claude-log: $file has no user/assistant turns" >&2; return 1; }
    total=$(printf '%s\n' "$lines" | wc -l)
    if [ "$n" -lt 0 ]; then n=$((total + n + 1)); fi
    if [ "$n" -lt 1 ] || [ "$n" -gt "$total" ]; then
        echo "claude-log: --turn $2 out of range (have $total turns)" >&2
        return 2
    fi
    printf '%s\n' "$lines" | sed -n "${n}p"
}

if [ "${1:-}" = "--_render" ]; then
    render_record "$2" "$3"
    exit 0
fi
if [ "${1:-}" = "--_summary" ]; then
    summarize_session "$2"
    exit 0
fi
if [ "${1:-}" = "--_list-sessions" ]; then
    list_sessions "$2"
    exit 0
fi
if [ "${1:-}" = "--_render-pretty" ]; then
    {
        print_header "$3" "$2"
        render_record "$2" "$3"
    } | if   command -v glow >/dev/null 2>&1; then glow -
        elif command -v bat  >/dev/null 2>&1; then bat --language=markdown --style=plain --paging=never
        else cat
        fi
    exit 0
fi

PRETTY=
NEWEST=
TURN=
SESSION=
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --pretty)  PRETTY=1 ;;
        --newest)  NEWEST=1 ;;
        --turn)    shift; TURN="${1:-}" ;;
        --turn=*)  TURN="${1#--turn=}" ;;
        -*)        echo "claude-log: unknown flag: $1" >&2; exit 2 ;;
        *)
            if [ -n "$SESSION" ]; then
                echo "claude-log: extra argument: $1" >&2; exit 2
            fi
            SESSION="$1"
            ;;
    esac
    shift
done

if [ -n "$TURN" ]; then
    case "$TURN" in
        -*[!0-9]*|*[!0-9-]*|-|'')
            echo "claude-log: --turn requires an integer, got: '$TURN'" >&2; exit 2 ;;
    esac
fi

# Start the picker in "all" scope if the current dir has no sessions, so the
# user still has something to pick from. ctrl-a always reloads to "all".
pick_session() {
    local scope prompt
    if [ -d "$PROJECT_DIR" ] && find "$PROJECT_DIR" -maxdepth 1 -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
        scope=project
        prompt='session> '
    elif [ -d "$HOME/.claude/projects" ]; then
        scope=all
        prompt='all> '
    else
        echo "claude-log: no sessions found under ~/.claude/projects" >&2
        return 1
    fi
    list_sessions "$scope" \
        | fzf --prompt="$prompt" --reverse --height=60% --ansi \
              --delimiter=$'\t' --with-nth=1 \
              --preview="$self --_summary {2}" \
              --preview-window=right,60%,wrap \
              --bind='alt-p:toggle-preview' \
              --bind="ctrl-a:reload($self --_list-sessions all)+change-prompt(all> )" \
              --footer=$'\033[2menter\033[0m pick   \033[2malt-p\033[0m preview   \033[2mctrl-a\033[0m all projects' \
              --wrap-sign='' \
        | cut -f2
}

if [ -n "$NEWEST" ] && [ -z "$SESSION" ]; then
    SESSION=$(newest_in_project) || true
    if [ -z "$SESSION" ]; then
        echo "claude-log: --newest: no sessions in $PROJECT_DIR" >&2
        exit 1
    fi
fi

if [ -z "$SESSION" ]; then
    SESSION=$(pick_session) || exit 1
    [ -n "$SESSION" ] || exit 0
fi

if [ ! -f "$SESSION" ]; then
    echo "claude-log: $SESSION not found" >&2
    exit 1
fi

# One row per displayable record: <line_no> \t <kind> \t <snippet>.
# Uses input_line_number so the row's line maps directly back to the JSONL.
turn_lines() {
    jq -r '
        select(.type == "user" or .type == "assistant") |
        [ input_line_number,
          (if .type == "assistant" then
               (.message.content // []) | map(.type) | join(",")
           else
               (if (.message.content | type) == "string" then "user" else "tool_result" end)
           end),
          (if .type == "assistant" then
               ((.message.content // []) | map(
                   if   .type == "text"     then .text
                   elif .type == "thinking" then "[think] " + (.thinking // "")
                   elif .type == "tool_use" then "[" + .name + "] " + ((.input | tojson)[0:80])
                   else "" end
               ) | join(" "))
           else
               (if (.message.content | type) == "string" then .message.content
                else (.message.content | map(
                    if .type == "tool_result" then
                        (if (.content | type) == "string" then .content
                         else (.content | map(.text // "") | join(" ")) end)
                    else "" end
                ) | join(" "))
                end)
           end)
        ] | @tsv
    ' "$SESSION" \
    | awk -F'\t' 'BEGIN{OFS="\t"} {
        s=$3; gsub(/[\n\r]/, " ", s);
        if (length(s)>120) s=substr(s,1,120)"…";
        # Color per kind. Priority matters for multi-content assistants
        # (e.g. "text,tool_use" → treat as text).
        col=""; sc=""
        if      ($2 ~ /text/)        { col="\033[1;36m" }
        else if ($2 == "user")       { col="\033[1;33m" }
        else if ($2 ~ /tool_result/) { col="\033[32m";  sc="\033[2m" }
        else if ($2 ~ /tool_use/)    { col="\033[35m";  sc="\033[2m" }
        else if ($2 ~ /thinking/)    { col="\033[2m";   sc="\033[2m" }
        rst="\033[0m"
        # Line number stays plain so fzf {1} can pass it as a clean integer.
        printf "%4d\t%s%-12s%s\t%s%s%s\n", $1, col, $2, rst, sc, s, rst
      }'
}

if [ -n "$TURN" ]; then
    selected=$(nth_turn_line "$SESSION" "$TURN") || exit $?
else
    selected=$(turn_lines \
        | fzf --prompt='turn> ' --reverse --tac --ansi \
              --delimiter=$'\t' --with-nth=1,2,3 \
              --preview="$self --_render {1} \"$SESSION\"" \
              --preview-window=right,60%,wrap \
              --bind='alt-p:toggle-preview' \
              --bind="alt-enter:become($self --_render-pretty {1} \"$SESSION\")" \
              --footer=$'\033[2menter\033[0m print   \033[2malt-enter\033[0m pretty   \033[2malt-p\033[0m preview' \
              --wrap-sign='' \
        | awk '{print $1}')
fi

[ -n "$selected" ] || exit 0

output_with_header() {
    print_header "$SESSION" "$selected"
    render_record "$selected" "$SESSION"
}

if [ -n "$PRETTY" ] && [ -t 1 ]; then
    if   command -v glow >/dev/null 2>&1; then output_with_header | glow -
    elif command -v bat  >/dev/null 2>&1; then output_with_header | bat --language=markdown --style=plain --paging=never
    else                                       output_with_header
    fi
else
    output_with_header
fi
