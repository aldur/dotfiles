{
  stdenvNoCC,
  agent-log,
}:

# The pickers need a terminal. This test examines all the other functions.
# Each example file uses the format of its agent. Thus a change to a format
# stops the build, and does not make an empty column.
stdenvNoCC.mkDerivation {
  name = "agent-log-test";

  nativeBuildInputs = [ agent-log ];

  buildCommand = ''
    set -euo pipefail
    work=$(mktemp -d)
    cd "$work"

    cat > claude.jsonl <<'EOF'
{"type":"user","timestamp":"2026-08-10T10:00:00.000Z","cwd":"/tmp/project","message":{"role":"user","content":"CLAUDEUSERMARK"}}
{"type":"assistant","timestamp":"2026-08-10T10:00:05.000Z","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"thinking","thinking":"CLAUDETHINKMARK"},{"type":"tool_use","name":"CLAUDETOOLMARK","input":{"command":"ls"}},{"type":"text","text":"CLAUDEANSWERMARK"}]}}
{"type":"user","timestamp":"2026-08-10T10:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"CLAUDERESULTMARK"}]}}
{"type":"ai-title","aiTitle":"CLAUDETITLEMARK"}
EOF

    cat > pi.jsonl <<'EOF'
{"type":"session","version":3,"id":"s1","cwd":"/tmp/project","timestamp":"2026-08-10T11:00:00.000Z"}
{"type":"model_change","provider":"llama-cpp","modelId":"PIMODELMARK","timestamp":"2026-08-10T11:00:00.000Z"}
{"type":"message","timestamp":"2026-08-10T11:00:01.000Z","message":{"role":"user","content":"PIUSERMARK"}}
{"type":"message","timestamp":"2026-08-10T11:00:02.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"PITHINKMARK"},{"type":"toolCall","id":"c1","name":"PITOOLMARK","arguments":{"p":1}},{"type":"text","text":"PIANSWERMARK"}]}}
EOF

    # The Codex format, from its documentation. The machine had no Codex
    # session. Thus this example file is the only test of that reader.
    cat > codex.jsonl <<'EOF'
{"timestamp":"2026-08-10T12:00:00.000Z","type":"session_meta","payload":{"id":"c1","cwd":"/tmp/project","instructions":"be terse"}}
{"timestamp":"2026-08-10T12:00:01.000Z","type":"turn_context","payload":{"cwd":"/tmp/project","model":"CODEXMODELMARK"}}
{"timestamp":"2026-08-10T12:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"CODEXUSERMARK"}]}}
{"timestamp":"2026-08-10T12:00:03.000Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"CODEXTHINKMARK"}]}}
{"timestamp":"2026-08-10T12:00:04.000Z","type":"response_item","payload":{"type":"function_call","name":"CODEXTOOLMARK","arguments":"{\"cmd\":\"ls\"}"}}
{"timestamp":"2026-08-10T12:00:05.000Z","type":"response_item","payload":{"type":"function_call_output","output":"CODEXRESULTMARK"}}
{"timestamp":"2026-08-10T12:00:06.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"CODEXANSWERMARK"}]}}
EOF

    cat > wire.jsonl <<'EOF'
{"id":1,"at":"2026-08-10T13:00:00.000Z","state":"open","method":"POST","path":"/v1/chat/completions","request":{"model":"WIREMODELMARK","messages":[{"role":"system","content":"WIRESYSMARK"},{"role":"user","content":"WIREUSERMARK"}]}}
{"id":1,"at":"2026-08-10T13:00:00.000Z","state":"done","method":"POST","path":"/v1/chat/completions","status":200,"request":{"model":"WIREMODELMARK","messages":[{"role":"system","content":"WIRESYSMARK"},{"role":"user","content":"WIREUSERMARK"}]},"response":"data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"WIRETHINKMARK\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"WIREANSWERMARK\"}}]}\n\ndata: [DONE]\n\n","prompt":"WIRERENDEREDMARK","promptTokens":42}
{"id":2,"at":"2026-08-10T13:05:00.000Z","state":"open","method":"POST","path":"/v1/chat/completions","request":{"messages":[{"role":"user","content":"WIRESTALLEDMARK"}]}}
EOF

    check() {
        local file="$1"; shift
        local out
        out=$(agent-log --full "$file")
        for mark in "$@"; do
            printf '%s' "$out" | grep -- "$mark" > /dev/null \
                || { echo "MISSING $mark in $file"; printf '%s\n' "$out"; exit 1; }
        done
    }

    echo "=== detection and rendering, one fixture per agent ==="
    check claude.jsonl CLAUDETITLEMARK CLAUDEUSERMARK CLAUDETHINKMARK CLAUDETOOLMARK CLAUDEANSWERMARK CLAUDERESULTMARK
    echo "  ✓ claude"
    check pi.jsonl PIMODELMARK PIUSERMARK PITHINKMARK PITOOLMARK PIANSWERMARK
    # A pi session does not contain these items. The reader must show this,
    # or a person can conclude that pi sent no system prompt.
    agent-log --full pi.jsonl | grep "no system prompt" > /dev/null
    echo "  ✓ pi"
    check codex.jsonl CODEXMODELMARK CODEXUSERMARK CODEXTHINKMARK CODEXTOOLMARK CODEXANSWERMARK CODEXRESULTMARK
    agent-log --full codex.jsonl | grep "not been checked against a real session" > /dev/null
    echo "  ✓ codex"
    check wire.jsonl WIRESYSMARK WIREUSERMARK
    # An exchange contains a full conversation and a sequence of parts. Thus
    # the reader makes it again, and does not use the line for the search.
    wire=$(agent-log _show 1 wire.jsonl --color=always)
    printf '%s' "$wire" | grep -- "▌ done 200" > /dev/null
    printf '%s' "$wire" | grep -- "▌ system" > /dev/null
    printf '%s' "$wire" | grep -- "▌ user" > /dev/null
    printf '%s' "$wire" | grep -- "▌ thinking" > /dev/null
    printf '%s' "$wire" | grep "WIRETHINKMARK" > /dev/null
    printf '%s' "$wire" | grep -- "▌ answer" > /dev/null
    printf '%s' "$wire" | grep "WIREANSWERMARK" > /dev/null
    printf '%s' "$wire" | grep "42 prompt tokens" > /dev/null
    # An exchange without a response shows a message, and not an empty
    # answer.
    agent-log _show 2 wire.jsonl | grep "No response recorded" > /dev/null
    echo "  ✓ wire"

    echo "=== turn addressing ==="
    agent-log --turn 1 claude.jsonl | grep CLAUDEUSERMARK > /dev/null
    agent-log --turn -1 claude.jsonl | grep CLAUDERESULTMARK > /dev/null
    agent-log --turn 1 codex.jsonl  | grep CODEXUSERMARK > /dev/null
    agent-log --turn -1 codex.jsonl | grep CODEXANSWERMARK > /dev/null
    if agent-log --turn 99 claude.jsonl 2>/dev/null; then echo "out-of-range turn should fail"; exit 1; fi
    echo "  ✓ turns"

    echo "=== wire exchanges collapse to one row each ==="
    rows=$(agent-log --list wire.jsonl)
    test "$(printf '%s\n' "$rows" | grep -c .)" -eq 2
    printf '%s' "$rows" | grep "done 200" > /dev/null
    printf '%s' "$rows" | grep "in flight" > /dev/null
    # The label must be the text that a person wrote. The system prompt starts
    # each request, thus it makes all the rows the same.
    printf '%s\n' "$rows" | grep "done 200" | cut -f4 | grep WIREUSERMARK > /dev/null
    ! printf '%s\n' "$rows" | grep "done 200" | cut -f4 | grep -q WIRESYSMARK
    echo "  ✓ wire exchanges"

    echo "=== picker plumbing the keybinds depend on ==="
    # Each sequence is a separate read of the rows. Thus the two sequences
    # must be different, and one must be the opposite of the other.
    newest=$(agent-log _turns codex.jsonl new)
    oldest=$(agent-log _turns codex.jsonl old)
    test "$newest" != "$oldest"
    test "$(printf '%s\n' "$oldest" | tac)" = "$newest"

    # ctrl-o must change the sequence in the two directions. A command that
    # always uses the same sequence is not an option.
    from_new=$(FZF_PROMPT="turn newest-first> " agent-log _order codex.jsonl)
    from_old=$(FZF_PROMPT="turn oldest-first> " agent-log _order codex.jsonl)
    printf '%s' "$from_new" | grep "codex.jsonl' old" > /dev/null
    printf '%s' "$from_new" | grep "change-prompt(turn oldest-first> )" > /dev/null
    printf '%s' "$from_old" | grep "codex.jsonl' new" > /dev/null
    printf '%s' "$from_old" | grep "change-prompt(turn newest-first> )" > /dev/null

    # fzf gives an action string to `$SHELL -c`, and the name of a project
    # directory can contain shell syntax. Thus each emitted action must
    # single-quote the path.
    cp codex.jsonl 'evil$(touch pwned).jsonl'
    FZF_PROMPT="turn newest-first> " agent-log _order 'evil$(touch pwned).jsonl' \
        | grep -F "'evil\$(touch pwned).jsonl'" > /dev/null
    FZF_PROMPT="turn newest-first> " agent-log _page_action 'evil$(touch pwned).jsonl' \
        | grep -F "'evil\$(touch pwned).jsonl'" > /dev/null
    test ! -e pwned

    # The earliest turn is at one of the two ends of the list. The current
    # sequence gives its position.
    test "$(FZF_PROMPT="turn newest-first> " agent-log _jump earliest)" = last
    test "$(FZF_PROMPT="turn newest-first> " agent-log _jump latest)"   = first
    test "$(FZF_PROMPT="turn oldest-first> " agent-log _jump earliest)" = first
    test "$(FZF_PROMPT="turn oldest-first> " agent-log _jump latest)"   = last

    # A footer that does not agree with the program is incorrect. Thus --help
    # must contain each key of a footer. The text for alt-i must also agree
    # with its result, which is the session id and not the path.
    help=$(agent-log --help)
    for which in session turn; do
        for key in $(agent-log _footer "$which" | tr -s ' ' '\n' | grep -E '^(enter|tab/shift-tab|alt-[a-zA-Z]+|ctrl-[a-z]+)$'); do
            for part in $(printf '%s' "$key" | tr '/' ' '); do
                printf '%s' "$help" | grep -- "$part" > /dev/null \
                    || { echo "$which footer advertises $part, --help never mentions it"; exit 1; }
            done
        done
    done
    agent-log _footer session | grep "alt-i id" > /dev/null
    ! agent-log _footer session | grep "path" > /dev/null
    ! agent-log _footer turn | grep "path" > /dev/null
    state() { sed 's/.*change-prompt(\([^)]*\)).*/\1/'; }

    # A person reads a conversation from the oldest turn to the newest turn.
    # Thus the picker opens in that sequence, and the options start from it.
    test "$(agent-log _prompt)" = "turn oldest-first> "
    test "$(FZF_PROMPT="$(agent-log _prompt)" agent-log _order codex.jsonl | state)" \
       = "turn newest-first> "
    test "$(FZF_PROMPT="$(agent-log _prompt)" agent-log _jump earliest)" = first
    test "$(FZF_PROMPT="$(agent-log _prompt)" agent-log _jump latest)" = last

    # ctrl-t removes the tool blocks. The two options are both in the prompt,
    # because a key command can read only the prompt. Thus each option must
    # keep the other one.
    test "$(FZF_PROMPT="turn newest-first> " agent-log _tools codex.jsonl | state)" \
       = "turn newest-first · dialogue> "
    test "$(FZF_PROMPT="turn newest-first · dialogue> " agent-log _tools codex.jsonl | state)" \
       = "turn newest-first> "
    test "$(FZF_PROMPT="turn oldest-first · dialogue> " agent-log _order codex.jsonl | state)" \
       = "turn newest-first · dialogue> "
    test "$(FZF_PROMPT="turn oldest-first · dialogue> " agent-log _tools codex.jsonl | state)" \
       = "turn oldest-first> "
    # The reload it emits must actually carry the flag.
    FZF_PROMPT="turn newest-first> " agent-log _tools codex.jsonl | grep -- "--no-tools" > /dev/null

    # And the filtered listing really is shorter, with no tool rows left.
    all_rows=$(agent-log _turns codex.jsonl new --color=never | grep -c .)
    dialogue=$(agent-log _turns codex.jsonl new --no-tools --color=never | grep -c .)
    test "$dialogue" -lt "$all_rows"
    ! agent-log _turns codex.jsonl new --no-tools --color=never | cut -f2 | grep "tool" > /dev/null

    # alt-a opens the whole conversation in whichever view is showing.
    FZF_PROMPT="turn newest-first · dialogue> " agent-log _page_action codex.jsonl \
        | grep -- "--no-tools" > /dev/null
    ! FZF_PROMPT="turn newest-first> " agent-log _page_action codex.jsonl \
        | grep -- "--no-tools" > /dev/null
    echo "  ✓ ordering, tool toggle, jumps and keybind help"

    echo "=== identifiers, tool blocks, colour and pipes ==="
    # alt-i must give the session id, because a resume command takes that
    # value. Thus the id is a field of the row, and not the path.
    test "$(agent-log --list wire.jsonl | head -1 | awk -F'\t' '{print NF}')" -ge 4

    # The id of each format. Claude and wire use the name of the file. pi and
    # Codex record an id.
    hdr=$(agent-log --turn 1 pi.jsonl)
    printf '%s' "$hdr" | grep "session: s1" > /dev/null
    printf '%s' "$hdr" | grep "title:" > /dev/null
    printf '%s' "$hdr" | grep "when:" > /dev/null
    # The header must give the model that made a turn.
    printf '%s' "$hdr" | grep "model:   llama-cpp/PIMODELMARK" > /dev/null
    agent-log --turn 1 claude.jsonl | grep "model:   claude-opus-5" > /dev/null
    agent-log --turn 1 codex.jsonl | grep "model:   CODEXMODELMARK" > /dev/null
    agent-log --turn 1 codex.jsonl | grep "session: c1" > /dev/null
    agent-log --turn 1 claude.jsonl | grep "session: claude" > /dev/null

    # Exactly one blank line comes after each rule. Two different forms of the
    # rule looked like a defect.
    for fixture in claude.jsonl pi.jsonl codex.jsonl; do
        # Do not use the name `out`. That is the output path of the
        # derivation.
        rendered=$(agent-log --turn 1 "$fixture")
        after=$(printf '%s\n' "$rendered" | grep -A1 -- "──────" | sed -n 2p)
        test -z "$after" || { echo "$fixture: rule not followed by a blank line: '$after'"; exit 1; }
    done

    # Each command that shows a turn must also show the header.
    for invocation in "--turn 1" "_show 3"; do
        # shellcheck disable=SC2086
        agent-log $invocation claude.jsonl 2>/dev/null | grep "^session: " > /dev/null \
            || { echo "no header from: agent-log $invocation"; exit 1; }
    done

    # --no-tools removes the tool blocks and not the full turns. An assistant
    # turn frequently contains the thinking, a tool call and the answer.
    dialogue=$(agent-log --full --no-tools claude.jsonl)
    printf '%s' "$dialogue" | grep CLAUDEANSWERMARK > /dev/null
    printf '%s' "$dialogue" | grep CLAUDETHINKMARK > /dev/null
    ! printf '%s' "$dialogue" | grep CLAUDETOOLMARK > /dev/null
    ! printf '%s' "$dialogue" | grep CLAUDERESULTMARK > /dev/null
    # A turn with only a tool result becomes empty, thus the reader removes
    # it.
    test "$(printf '%s' "$dialogue" | grep -c "^## ")" -lt \
         "$(agent-log --full claude.jsonl | grep -c "^## ")"

    # --pretty must do nothing if the output is not a terminal. If not, each
    # file gets different line breaks.
    test "$(agent-log --full claude.jsonl)" = "$(agent-log --full --pretty claude.jsonl)"

    # Rust disables SIGPIPE, and a command with `| head` is usual.
    agent-log --list wire.jsonl | head -1 > /dev/null
    err=$(agent-log --list wire.jsonl 2>&1 >/dev/null | head -c 100 || true)
    test -z "$err"
    echo "  ✓ ids, --no-tools, --pretty, SIGPIPE"

    echo "=== both previews render a turn the same way ==="
    # The conversation view must not use the single line for the search,
    # because that line has no line breaks.
    conv=$(agent-log _full claude.jsonl --color=always)
    turn=$(agent-log _show 2 claude.jsonl --color=always)
    for fragment in "▌ tool: CLAUDETOOLMARK" "▌ thinking"; do
        printf '%s' "$conv" | grep -- "$fragment" > /dev/null \
            || { echo "conversation view lacks: $fragment"; exit 1; }
        printf '%s' "$turn" | grep -- "$fragment" > /dev/null \
            || { echo "turn view lacks: $fragment"; exit 1; }
    done
    # The two views show the arguments of a tool on more than one line.
    printf '%s' "$conv" | grep '"command": "ls"' > /dev/null
    printf '%s' "$turn" | grep '"command": "ls"' > /dev/null

    # The conversation view uses the same header as the turn view. The
    # patterns have no start anchor, because escape sequences are around the
    # labels when colour is on.
    # The patterns also have no space at the end, because a reset sequence is
    # between a label and its value.
    printf '%s' "$conv" | grep "session:" > /dev/null
    printf '%s' "$conv" | grep "model:" > /dev/null
    printf '%s' "$conv" | grep "claude-opus-5" > /dev/null
    printf '%s' "$turn" | grep "session:" > /dev/null
    ! printf '%s' "$conv" | grep -- "# CLAUDETITLEMARK" > /dev/null

    # Without colour, the conversation view uses markdown, because the output
    # goes to a file, a pager or glow.
    agent-log --full claude.jsonl | grep "^## " > /dev/null
    agent-log --full claude.jsonl | grep "^# CLAUDETITLEMARK" > /dev/null
    ! agent-log --full claude.jsonl | grep -- "▌" > /dev/null

    # A warning is part of the header in the two modes. A blank line is
    # always between the warning and the first turn.
    agent-log --full pi.jsonl | grep "^> A pi session" > /dev/null
    agent-log _full pi.jsonl --color=always | grep "A pi session" > /dev/null
    # A `cmd && { fail; }` construction stops the script with `set -e` when
    # `cmd` fails. Here that condition is the correct result.
    for mode in "--full" "_full"; do
        # shellcheck disable=SC2086
        following=$(agent-log $mode pi.jsonl | grep -A1 "pi-wire-proxy for those" | sed -n 2p)
        if [ -n "$following" ]; then
            echo "$mode: caveat runs into '$following'"
            exit 1
        fi
    done
    # ...and still carries the multi-line body, not the flattened line.
    agent-log --full claude.jsonl | grep '"command": "ls"' > /dev/null
    echo "  ✓ conversation and turn views agree"

    echo "=== scoped scanning skips directories without changing results ==="
    # A store in the format of Claude and pi. The name of a project directory
    # is the working directory, with a dash in place of each separator.
    store="$work/home/.claude/projects"
    mkdir -p "$store/-tmp-project" "$store/-tmp-elsewhere"
    sed 's#/tmp/project#/tmp/project#' claude.jsonl > "$store/-tmp-project/a.jsonl"
    sed 's#/tmp/project#/tmp/elsewhere#' claude.jsonl > "$store/-tmp-elsewhere/b.jsonl"

    mkdir -p /tmp/project
    scoped=$(cd /tmp/project && HOME="$work/home" agent-log --list | grep -c .)
    every=$(HOME="$work/home" agent-log --all --list | grep -c .)
    test "$scoped" -eq 1
    test "$every" -eq 2

    # The program must also find a directory with a different name. The filter
    # is only for speed, and must not change the results.
    mkdir -p "$store/an-unrelated-name"
    sed 's#/tmp/project#/tmp/oddly-named#' claude.jsonl > "$store/an-unrelated-name/c.jsonl"
    mkdir -p /tmp/oddly-named
    odd=$(cd /tmp/oddly-named && HOME="$work/home" agent-log --list | grep -c .)
    test "$odd" -eq 1
    echo "  ✓ prefilter narrows without losing sessions"

    echo "=== colour is a decision, not an accident ==="
    esc=$(printf '\033')
    # Output to a pipe or a file has no escape sequences, for all the possible
    # content of a transcript.
    test "$(agent-log --turn 1 claude.jsonl | tr -dc "$esc" | wc -c)" -eq 0
    test "$(agent-log --list wire.jsonl | tr -dc "$esc" | wc -c)" -eq 0
    test "$(agent-log --full claude.jsonl | tr -dc "$esc" | wc -c)" -eq 0
    # --color=always gives colour, because fzf shows the colours in a
    # preview.
    test "$(agent-log --turn 1 --color=always claude.jsonl | tr -dc "$esc" | wc -c)" -gt 0
    # NO_COLOR has priority over --color=always.
    test "$(NO_COLOR=1 agent-log --turn 1 --color=always claude.jsonl | tr -dc "$esc" | wc -c)" -eq 0

    # A transcript can contain the output of a terminal. The program removes
    # the escape sequences from the rows and the titles.
    # An escape byte in a JSON text is not correct JSON. A transcript uses
    # \u001b, and the reader must accept that form.
    cat > ansi.jsonl <<'ANSI'
{"type":"user","timestamp":"2026-08-10T10:00:00.000Z","cwd":"/tmp","message":{"role":"user","content":"before \u001b[1mBOLD\u001b[0m after"}}
{"type":"ai-title","aiTitle":"t \u001b[36mCOLOUR\u001b[0m x"}
ANSI
    test "$(agent-log --list ansi.jsonl | tr -dc "$esc" | wc -c)" -eq 0
    agent-log --list ansi.jsonl | cut -f5 | grep "before BOLD after" > /dev/null
    agent-log --full ansi.jsonl | head -1 | grep "t COLOUR x" > /dev/null
    # The full view and the turn view print the body of a turn to the
    # terminal or to a pager. The sequences must not survive there.
    test "$(agent-log --full ansi.jsonl | tr -dc "$esc" | wc -c)" -eq 0
    agent-log --full ansi.jsonl | grep "before BOLD after" > /dev/null
    agent-log _show 1 ansi.jsonl --color=never | grep "before BOLD after" > /dev/null
    echo "  ✓ colour, NO_COLOR, escape stripping"

    echo "=== a file that is not a transcript is rejected, not guessed at ==="
    printf '{"type":"started","key":"v2:abc"}\n' > journal.jsonl
    if agent-log --full journal.jsonl 2>/dev/null | grep -q "^## "; then
        echo "journal.jsonl should not parse as a conversation"; exit 1
    fi
    echo "  ✓ rejection"

    mkdir -p $out
    echo "claude, pi, codex and wire transcripts all read" > $out/result
  '';
}
