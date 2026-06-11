usage() {
    cat <<'EOF'
Usage: claude-log [--pretty] [--full] [--newest] [--turn N] [PATH]

Interactively browse a Claude Code session transcript.

PATH may be a session .jsonl file (opens it directly) or a directory.
A directory is treated as a project and scopes the picker to it —
either a ~/.claude/projects/<encoded> dir or a working directory
(encoded the way Claude Code does). Combine with --newest/--full/--turn
to act on that project's newest session.

If PATH is omitted, picks among sessions for the current project
(~/.claude/projects/<encoded-cwd>/*.jsonl), most recently active
first (ordered by last message timestamp, not file mtime).

In the session picker (type to full-text search the whole conversation —
prompts, replies, thinking, tool calls and results — by exact substring;
space separates AND terms):
  enter      open the session in the turn picker
  alt-a      view the full conversation in a pager (returns to the picker)
  alt-v      open the full conversation in nvim (read-only markdown)
  alt-i      print the session id and exit — handy for `claude --resume <id>`
  alt-p      toggle the preview pane
  ctrl-a     broaden to sessions from all projects

In the turn picker (rows are timestamped; type to full-text search the
entire text of every turn by exact substring, not just the visible snippet):
  enter      print the selected turn(s)
  tab        mark/unmark a turn and move down (multi-select)
  shift-tab  mark/unmark a turn and move up (extend a range)
  alt-enter  print the focused turn, rendered via glow/bat
  alt-a      view the full conversation in a pager (returns to the picker)
  alt-v      open the full conversation in nvim (read-only markdown)
  ctrl-o     toggle ordering (newest-first ↔ oldest-first)
  alt-g      jump to the earliest message; alt-G jumps to the latest
  alt-p      toggle the preview pane

Marked turns are printed together in chronological order (Tab order doesn't
matter); enter with nothing marked prints just the focused turn.

Options:
  --newest      Skip the picker; open the most recently active session in cwd.
  --full        Print the whole conversation (markdown) and exit; redirect to
                a file to export it. With --pretty, opens it in a pager.
  --no-tools    With --full, omit tool calls/results (dialogue-only transcript).
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
# The session list slurps and extracts text from hundreds of files; that work
# is dominated by JSON string handling, where jq is slow. jaq (a Rust jq) does
# it ~7x faster with identical output, so use it for that hot path when present
# and fall back to jq. Other jq uses rely on jq-only builtins and stay on jq.
fastjq=$(command -v jaq 2>/dev/null || command -v jq 2>/dev/null || echo jq)

# Build one fzf row for a single session file, reading it exactly once.
# Output: <epoch_sort_key>\t<colored display>\t<path>\t<corpus>
# The whole file is slurped in a single pass ($fastjq = jaq/jq) that extracts
# the last timestamp, the title (or first user message as a fallback), and the
# searchable corpus — replacing the old four-process-per-file approach.
# Whitespace is flattened with literal split/join (jq's regex gsub is
# pathologically slow on large corpora). The corpus covers everything a person
# searches by: prompts (string or array-form text), assistant text, thinking,
# tool-call inputs, and tool results. The row is written to its own file under
# $tmpd so parallel workers never interleave on a shared pipe (corpus fields
# dwarf the kernel's atomic-write size).
session_row() {
    local scope="$1" tmpd="$2" path="$3"
    local row ts label corpus dt sort_key when project dir
    row=$("$fastjq" -rs '
        def flat: (. / "\t" | join(" ")) | (. / "\n" | join(" ")) | (. / "\r" | join(" "));
        # Searchable text per record: user prompts (string OR array-form text
        # blocks), assistant text, thinking, tool-call inputs, and tool results.
        # flat() collapses whitespace and keeps each session on one line.
        def alltext:
          if (.message.content | type) == "string" then (.message.content // "")
          else ((.message.content // []) | map(
              if   .type=="text"        then (.text // "")
              elif .type=="thinking"    then (.thinking // "")
              elif .type=="tool_use"    then (.name // "") + " " + (.input | tojson)
              elif .type=="tool_result" then (if (.content | type) == "string" then .content
                                               else ((.content // []) | map(.text // "") | join(" ")) end)
              else "" end
            ) | join(" "))
          end;
        # First typed user text (string or array text block) — label fallback
        # when a session has no ai-title; skips tool_result-only user records.
        def usertext:
          if (.message.content | type) == "string" then (.message.content // "")
          else ((.message.content // []) | map(select(.type=="text") | .text) | join(" ")) end;
        {
          ts:     ( [ .[] | .timestamp // empty ] | last // "" ),
          title:  ( [ .[] | select(.type=="ai-title") | .aiTitle ] | last // "" ),
          first:  ( [ .[] | select(.type=="user") | usertext | select(. != "") ] | first // "" ),
          corpus: ( [ .[] | select(.type=="user" or .type=="assistant") | alltext ] | join(" ") | flat )
        }
        | [ .ts,
            ( (if .title == "" then .first else .title end) | flat | .[0:100] ),
            .corpus ]
        | join("\t")
    ' "$path" 2>/dev/null | tr -d '\000') || return 0
    IFS=$'\t' read -r ts label corpus <<<"$row"
    # One date call yields both the epoch sort-key and the display string;
    # fall back to file mtime when the session has no .timestamp fields.
    if [ -n "$ts" ] && dt=$(date -d "$ts" $'+%s\t%Y-%m-%d %H:%M' 2>/dev/null); then
        sort_key=${dt%%$'\t'*}
        when=${dt#*$'\t'}
    else
        sort_key=$(stat -c %Y "$path" 2>/dev/null || echo 0)
        when=$(date -d "@${sort_key}" '+%Y-%m-%d %H:%M')
    fi
    # The corpus is shown dimmed (it trails the title and is truncated by fzf):
    # fzf couples display and search, so to search the corpus it must be part
    # of the displayed fields (--with-nth=1,3). The path stays field 2 — hidden
    # from display but still reachable via {2} for the preview and selection.
    if [ "$scope" = "all" ]; then
        dir=${path%/*}; project=${dir##*/}
        printf '%s\t\033[36m%s\033[0m  \033[2m[%s]\033[0m %s\t%s\t\033[2m%s\033[0m\n' \
            "$sort_key" "$when" "$project" "$label" "$path" "$corpus"
    else
        printf '%s\t\033[36m%s\033[0m  %s\t%s\t\033[2m%s\033[0m\n' \
            "$sort_key" "$when" "$label" "$path" "$corpus"
    fi > "$tmpd/${path##*/}"
}

# Emit one fzf row per session:  <colored display>\t<path>\t<corpus>
#   scope=project → just the current project's sessions
#   scope=all     → every session under ~/.claude/projects, prefixed with [project]
# Rows are built in parallel (one worker process per file); each writes to a
# private temp file, then we merge, sort by the epoch sort-key, and strip it.
list_sessions() {
    # tmpd is deliberately NOT local: the EXIT/INT/TERM trap below must see it
    # at signal time, including when a downstream `head` SIGPIPEs the merge
    # pipeline (and set -e unwinds the function before the explicit rm). Each
    # call runs in its own subshell/process, so a non-local cannot collide.
    local scope="$1" root maxdepth jobs
    if [ "$scope" = "all" ]; then
        root="$HOME/.claude/projects"
        maxdepth=2
    else
        root="$PROJECT_DIR"
        maxdepth=1
    fi
    [ -d "$root" ] || return 0
    # Use all cores, bounded so a huge core count can't fan out into too many
    # concurrent file slurps.
    jobs=$(nproc 2>/dev/null || echo 4)
    [ "$jobs" -gt 16 ] && jobs=16
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/claude-log.XXXXXX") || return 1
    trap 'rm -rf -- "$tmpd"' EXIT INT TERM
    # Batch files per worker (-n 16) so the bash startup + top-level init is
    # amortized across many files instead of paid once per file.
    find "$root" -mindepth 1 -maxdepth "$maxdepth" -name '*.jsonl' -print0 2>/dev/null \
        | xargs -0 -r -P "$jobs" -n 16 "$self" --_session-row "$scope" "$tmpd"
    find "$tmpd" -maxdepth 1 -type f -print0 2>/dev/null \
        | xargs -0 -r cat \
        | sort -rn -t $'\t' -k1,1 \
        | cut -f2-
    rm -rf -- "$tmpd"
    trap - EXIT INT TERM
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

# Pipe markdown on stdin through glow/bat when available, else pass through.
# Used for short, single-turn output. (Full conversations use page_md instead:
# glow reflows and truncates long lines/code blocks, which mangles transcripts.)
pretty_filter() {
    if   command -v glow >/dev/null 2>&1; then glow -
    elif command -v bat  >/dev/null 2>&1; then bat --language=markdown --style=plain --paging=never
    else cat
    fi
}

# View markdown on stdin in a scrollable pager that does NOT reflow/truncate, so
# nothing in a long conversation is lost. Prefer bat (highlighting + paging),
# then less; glow only as a last resort since it wraps and clips wide content.
page_md() {
    if   command -v bat  >/dev/null 2>&1; then bat --language=markdown --style=plain --paging=always
    elif command -v less >/dev/null 2>&1; then less -R
    elif command -v glow >/dev/null 2>&1; then glow -p -
    else cat
    fi
}

# Render the *entire* conversation as markdown: every user/assistant record in
# order, including text, (non-empty) thinking, tool calls, and tool results.
# A single `block`/`body` pair handles user and assistant content alike, so
# nothing is dropped (e.g. text blocks inside array-form user messages). Empty
# (redacted) thinking blocks are skipped rather than rendered as blank sections.
# Each header is stamped with the turn's local time. Arg 2 = "1" hides tool
# calls/results (the --no-tools dialogue-only export); passed via env so the jq
# program needs no $-variable (which shellcheck's SC2016 would flag).
render_full() {
    local file="$1" notools="${2:-}"
    CLAUDELOG_NO_TOOLS="$notools" jq -r '
        def block:
          if   .type=="text"        then (.text // "")
          elif .type=="thinking"    then
               (if (.thinking // "") == "" then ""
                else "> **thinking**\n>\n" + (.thinking | split("\n") | map("> " + .) | join("\n")) end)
          elif .type=="tool_use"    then
               (if env.CLAUDELOG_NO_TOOLS == "1" then ""
                else "**tool_use** `" + (.name // "?") + "`\n\n```json\n" + (.input | tojson) + "\n```" end)
          elif .type=="tool_result" then
               (if env.CLAUDELOG_NO_TOOLS == "1" then ""
                else "**tool_result**\n\n```\n" +
                     (if (.content | type) == "string" then .content
                      else ((.content // []) | map(.text // (. | tojson)) | join("\n")) end) + "\n```" end)
          elif .type=="image"       then "_[image]_"
          else "" end;
        def body:
          if (.message.content | type) == "string" then (.message.content // "")
          else ((.message.content // []) | map(block) | map(select(. != "")) | join("\n\n")) end;
        select(.type=="user" or .type=="assistant")
        | { role: .type,
            time: (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strflocaltime("%H:%M")) catch ""),
            body: body }
        | select(.body != "")
        | "\n## " + .role + (if .time == "" then "" else " · " + .time end) + "\n\n" + .body
    ' "$file"
}

# Full conversation with a title/session header, for `--full` and the picker.
# Arg 2 (optional, "1") is forwarded to render_full to hide tool calls/results.
output_full() {
    local file="$1" notools="${2:-}" uuid title
    uuid=$(basename "$file" .jsonl)
    title=$(jq -r 'select(.type=="ai-title") | .aiTitle' "$file" 2>/dev/null | tail -1)
    [ -n "$title" ] && printf '# %s\n\n' "$title"
    printf '_session %s_\n' "$uuid"
    render_full "$file" "$notools"
}

# Open the full conversation in nvim (read-only) as a named .md temp file, so
# the markdown filetype is detected and the buffer name is meaningful. Falls
# back to $VISUAL/$EDITOR/vi when nvim is absent. Bound to a picker key via
# execute(), which hands the editor the terminal and returns on quit.
# tmpd is intentionally non-local so the EXIT/INT/TERM trap can clean it even
# if the editor is killed; this subcommand runs in its own short-lived process.
edit_full() {
    local file="$1" md
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/claude-log.XXXXXX") || return 1
    trap 'rm -rf -- "$tmpd"' EXIT INT TERM
    md="$tmpd/$(basename "$file" .jsonl).md"
    output_full "$file" > "$md"
    if command -v nvim >/dev/null 2>&1; then
        nvim -R "$md"
    else
        "${VISUAL:-${EDITOR:-vi}}" "$md"
    fi
    rm -rf -- "$tmpd"
    trap - EXIT INT TERM
}

# One fzf row per record: <line_no> \t <kind> \t <time> \t <text>. The <text>
# field holds the record's ENTIRE text (untruncated, whitespace-flattened); fzf
# displays it truncated to the window width but matches against all of it, so
# the picker is a true full-text search. (fzf couples display and search — a
# field hidden via --with-nth is also unsearchable — so the full text must live
# in a shown field rather than a hidden trailing one.)
# input_line_number maps each row back to the JSONL; per-turn local time is
# derived in-process (no `date` fork per turn). Empty (redacted) thinking-only
# records produce no text and are dropped. order=old keeps chronological
# (oldest first); anything else reverses to newest-first (fzf's --tac only
# affects the initial load and can't be toggled live, so we order here).
turn_lines() {
    local file="$1" order="${2:-new}"
    jq -r '
        def flat: (. / "\t" | join(" ")) | (. / "\n" | join(" ")) | (. / "\r" | join(" "));
        select(.type == "user" or .type == "assistant")
        | { line: input_line_number,
            kind: (if .type == "assistant" then ((.message.content // []) | map(.type) | join(","))
                   else (if (.message.content | type) == "string" then "user" else "tool_result" end) end),
            time: (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strflocaltime("%H:%M")) catch ""),
            text: (
              if .type == "assistant" then
                ((.message.content // []) | map(
                    if   .type=="text"     then (.text // "")
                    elif .type=="thinking" then (if (.thinking // "") == "" then "" else "[think] " + .thinking end)
                    elif .type=="tool_use" then "[" + (.name // "?") + "] " + (.input | tojson)
                    else "" end
                ) | map(select(. != "")) | join(" "))
              else
                (if (.message.content | type) == "string" then (.message.content // "")
                 else ((.message.content // []) | map(
                     if .type=="tool_result" then
                         (if (.content | type) == "string" then .content
                          else ((.content // []) | map(.text // "") | join(" ")) end)
                     else "" end
                 ) | map(select(. != "")) | join(" ")) end)
              end ) }
        | select(.text != "")
        | [ (.line | tostring), .kind, .time, (.text | flat) ] | join("\t")
    ' "$file" \
    | tr -d '\000' \
    | awk -F'\t' 'BEGIN{OFS="\t"} {
        # Color per kind. Priority matters for multi-content assistants
        # (e.g. "text,tool_use" → treat as text).
        col=""; sc=""
        if      ($2 ~ /text/)        { col="\033[1;36m" }
        else if ($2 == "user")       { col="\033[1;33m" }
        else if ($2 ~ /tool_result/) { col="\033[32m";  sc="\033[2m" }
        else if ($2 ~ /tool_use/)    { col="\033[35m";  sc="\033[2m" }
        else if ($2 ~ /thinking/)    { col="\033[2m";   sc="\033[2m" }
        rst="\033[0m"
        # Columns: line (plain, so fzf {1} is a clean integer), kind, time, and
        # the full text. fzf truncates the text for display but searches all of
        # it; no separate hidden field (a hidden field would not be searched).
        printf "%4d\t%s%-12s%s\t\033[2m%5s\033[0m\t%s%s%s\n", $1, col, $2, rst, $3, sc, $4, rst
      }' \
    | if [ "$order" = old ]; then cat; else tac; fi
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
if [ "${1:-}" = "--_session-row" ]; then
    # Worker handles a batch of files (xargs -n 16). Best-effort per file: a bad
    # file is skipped, never aborting the batch.
    _scope="$2"; _tmpd="$3"; shift 3
    for _p in "$@"; do session_row "$_scope" "$_tmpd" "$_p" || true; done
    exit 0
fi
if [ "${1:-}" = "--_turn-lines" ]; then
    turn_lines "$2" "${3:-new}"
    exit 0
fi
if [ "${1:-}" = "--_render-pretty" ]; then
    { print_header "$3" "$2"; render_record "$2" "$3"; } | pretty_filter
    exit 0
fi
if [ "${1:-}" = "--_render-full" ]; then
    output_full "$2" | page_md
    exit 0
fi
if [ "${1:-}" = "--_edit-full" ]; then
    edit_full "$2"
    exit 0
fi
# Picker keybind helpers: read fzf's $FZF_PROMPT (which encodes the current
# order) and emit fzf actions on stdout for a transform() binding.
if [ "${1:-}" = "--_toggle-order" ]; then
    case "${FZF_PROMPT:-}" in
        *oldest*) printf 'reload("%s" --_turn-lines "%s" new)+change-prompt(turn newest-first> )+first' "$self" "$2" ;;
        *)        printf 'reload("%s" --_turn-lines "%s" old)+change-prompt(turn oldest-first> )+first' "$self" "$2" ;;
    esac
    exit 0
fi
if [ "${1:-}" = "--_jump" ]; then
    # "earliest"/"latest" are chronological; which end that is depends on order.
    case "$2" in
        earliest) case "${FZF_PROMPT:-}" in *oldest*) printf first ;; *) printf last  ;; esac ;;
        latest)   case "${FZF_PROMPT:-}" in *oldest*) printf last  ;; *) printf first ;; esac ;;
    esac
    exit 0
fi

PRETTY=
NEWEST=
TURN=
FULL=
NOTOOLS=
SESSION=
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --pretty)   PRETTY=1 ;;
        --newest)   NEWEST=1 ;;
        --full)     FULL=1 ;;
        --no-tools) NOTOOLS=1 ;;
        --turn)     shift; TURN="${1:-}" ;;
        --turn=*)   TURN="${1#--turn=}" ;;
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

# A positional argument may be a session .jsonl file (open it directly) or a
# directory. A directory is treated as a project and scopes the picker to it:
# either a ~/.claude/projects/<encoded> dir used as-is, or a working directory
# encoded the way Claude Code does (path separators and dots become dashes).
if [ -n "$SESSION" ] && [ -d "$SESSION" ]; then
    target=$(realpath -s -- "$SESSION" 2>/dev/null || printf '%s' "$SESSION")
    case "$target" in
        "$HOME/.claude/projects/"*) PROJECT_DIR="$target" ;;
        *) PROJECT_DIR="$HOME/.claude/projects/$(printf '%s' "$target" | tr '/.' '-')" ;;
    esac
    SESSION=
fi

# Start the picker in "all" scope if the current dir has no sessions, so the
# user still has something to pick from. ctrl-a always reloads to "all".
pick_session() {
    local scope prompt out key sel
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
    # --expect makes alt-i accept like enter while reporting itself on the
    # first output line, so the caller can print the bare session id and skip
    # the turn picker. Output is "<key>\n<selected row>"; key is empty on enter.
    out=$(list_sessions "$scope" \
        | fzf --prompt="$prompt" --reverse --height=60% --ansi \
              --delimiter=$'\t' --with-nth=1,3 --exact \
              --expect=alt-i \
              --preview="$self --_summary {2}" \
              --preview-window=right,60%,wrap \
              --bind='alt-p:toggle-preview' \
              --bind="alt-a:execute($self --_render-full {2})" \
              --bind="alt-v:execute($self --_edit-full {2})" \
              --bind="ctrl-a:reload($self --_list-sessions all)+change-prompt(all> )" \
              --footer=$'\033[2menter\033[0m open   \033[2malt-i\033[0m id only   \033[2malt-a\033[0m full convo   \033[2malt-v\033[0m nvim   \033[2malt-p\033[0m preview   \033[2mctrl-a\033[0m all projects' \
              --wrap-sign='') || return 1
    key=$(printf '%s\n' "$out" | sed -n 1p)
    sel=$(printf '%s\n' "$out" | sed -n 2p | cut -f2)
    [ -n "$sel" ] || return 0
    if [ "$key" = "alt-i" ]; then
        printf 'id\t%s\n' "$(basename "$sel" .jsonl)"
    else
        printf 'path\t%s\n' "$sel"
    fi
}

if [ -n "$NEWEST" ] && [ -z "$SESSION" ]; then
    SESSION=$(newest_in_project) || true
    if [ -z "$SESSION" ]; then
        echo "claude-log: --newest: no sessions in $PROJECT_DIR" >&2
        exit 1
    fi
fi

if [ -z "$SESSION" ]; then
    picked=$(pick_session) || exit 1
    [ -n "$picked" ] || exit 0
    # alt-i in the picker returns "id\t<uuid>" — print it and stop short of
    # the turn picker. A normal pick returns "path\t<file>".
    if [ "${picked%%$'\t'*}" = "id" ]; then
        printf '%s\n' "${picked#*$'\t'}"
        exit 0
    fi
    SESSION="${picked#*$'\t'}"
fi

if [ ! -f "$SESSION" ]; then
    echo "claude-log: $SESSION not found" >&2
    exit 1
fi

# --full: dump the whole conversation and stop (no turn picker). Plain markdown
# to stdout by default (redirect to a file); --pretty opens it in a pager.
# --no-tools drops tool calls/results for a dialogue-only transcript.
if [ -n "$FULL" ]; then
    if [ -n "$PRETTY" ] && [ -t 1 ]; then
        output_full "$SESSION" "$NOTOOLS" | page_md
    else
        output_full "$SESSION" "$NOTOOLS"
    fi
    exit 0
fi

if [ -n "$TURN" ]; then
    selected=$(nth_turn_line "$SESSION" "$TURN") || exit $?
else
    # Default to newest-first (matching the old --tac behaviour); the prompt
    # text encodes the current order so the toggle/jump keybinds can read it
    # back via $FZF_PROMPT.
    selected=$(turn_lines "$SESSION" new \
        | fzf --prompt='turn newest-first> ' --reverse --ansi \
              --delimiter=$'\t' --with-nth=1,2,3,4 --exact --multi \
              --preview="$self --_render {1} \"$SESSION\"" \
              --preview-window=right,60%,wrap \
              --bind='alt-p:toggle-preview' \
              --bind="alt-enter:become($self --_render-pretty {1} \"$SESSION\")" \
              --bind="alt-a:execute($self --_render-full \"$SESSION\")" \
              --bind="alt-v:execute($self --_edit-full \"$SESSION\")" \
              --bind="ctrl-o:transform($self --_toggle-order \"$SESSION\")" \
              --bind="alt-g:transform($self --_jump earliest)" \
              --bind="alt-G:transform($self --_jump latest)" \
              --footer=$'\033[2menter\033[0m print   \033[2mtab/S-tab\033[0m mark +/- (multi)   \033[2malt-enter\033[0m pretty   \033[2malt-a\033[0m full convo   \033[2malt-v\033[0m nvim   \033[2mctrl-o\033[0m order   \033[2malt-g/G\033[0m earliest/latest   \033[2malt-p\033[0m preview' \
              --wrap-sign='' \
        | awk '{print $1}')
fi

[ -n "$selected" ] || exit 0

# $selected may hold several line numbers (Tab-marked multi-select). Render each
# in chronological (line-number) order: the session header once, then each
# record separated by a rule. A single selection is unchanged.
print_selected() {
    local ln first=1
    while IFS= read -r ln; do
        [ -n "$ln" ] || continue
        if [ -n "$first" ]; then
            first=
            print_header "$SESSION" "$ln"
        else
            printf '\n──────────────────────────────────────────────────────────────\n\n'
        fi
        render_record "$ln" "$SESSION"
    done < <(printf '%s\n' "$selected" | sort -n)
}

if [ -n "$PRETTY" ] && [ -t 1 ]; then
    print_selected | pretty_filter
else
    print_selected
fi
