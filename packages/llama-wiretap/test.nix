{
  stdenvNoCC,
  nodejs-slim,
  curl,
  jq,
  llama-wiretap,
}:

# Drives the proxy over both transports it supports against ./test-upstream.mjs,
# a stand-in llama-server. The transcript is checked against what the upstream
# was actually handed — including the rendered prompt and its token count, the
# two fields that are the reason this proxy exists.
stdenvNoCC.mkDerivation {
  name = "llama-wiretap-test";

  nativeBuildInputs = [
    nodejs-slim
    curl
    jq
    llama-wiretap
  ];

  buildCommand = ''
    set -euo pipefail

    work=$(mktemp -d)
    cd "$work"

    pids=""
    trap 'for p in $pids; do kill "$p" 2>/dev/null || true; done' EXIT

    # Every wait is bounded, so a transport that never comes up fails the
    # build instead of hanging the builder until its timeout.
    wait_for_path() {
      for _ in $(seq 1 100); do
        if [ -e "$1" ]; then return 0; fi
        sleep 0.1
      done
      echo "timed out waiting for $1" >&2
      exit 1
    }

    # Readiness against a listener that is already serving requests. Sent
    # through the proxy on purpose for the proxy's own probe: it proves the
    # whole path works, and leaves a record the probe assertions then use.
    wait_for_http() {
      for _ in $(seq 1 100); do
        if curl -s -o /dev/null --max-time 1 "$@" > /dev/null 2>&1; then return 0; fi
        sleep 0.1
      done
      echo "timed out waiting for $*" >&2
      exit 1
    }

    # The transcript is appended after the client's response completes — the
    # render round-trips to the upstream first — so the exchange under test is
    # not in the file the moment curl returns. Poll for the record itself
    # rather than for the file, which the readiness probe already created.
    wait_for_record() {
      for _ in $(seq 1 100); do
        if [ -s "$1" ] && jq -e --arg p "$2" 'select(.path == $p and .state == "done")' "$1" > /dev/null 2>&1; then
          return 0
        fi
        sleep 0.1
      done
      echo "timed out waiting for a completed $2 record in $1" >&2
      exit 1
    }

    # A whole thread, not a single turn: a chat-completions request re-sends the
    # entire history, and a coding agent's history is mostly tool traffic that
    # lives outside `content`.
    request='{"model":"m","stream":true,"messages":[{"role":"system","content":"SYSMARK"},{"role":"user","content":"USERMARK"},{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"TOOLMARK","arguments":"{\"p\":\"TOOLARGMARK\"}"}}]},{"role":"tool","tool_call_id":"call_1","content":"TOOLRESULTMARK"},{"role":"user","content":"FOLLOWUPMARK"}],"tools":[{"type":"function","function":{"name":"TOOLMARK","parameters":{}}}]}'

    # Every field the transcript is supposed to carry, checked in one place so
    # all three topologies get the same scrutiny.
    assert_transcript() {
      log="$1"
      sse="$2"

      # Selected by path and state rather than by line number: anything else
      # that crossed the proxy is legitimately in the file too, and every
      # exchange contributes an "open" record before its "done" one.
      record=$(jq -c 'select(.path == "/v1/chat/completions" and .state == "done")' "$log")
      test "$(printf '%s\n' "$record" | wc -l)" -eq 1

      # The stall signature the tool exists to show: the request is on record
      # from the moment it is forwarded, not only once a response comes back.
      opened=$(jq -c 'select(.path == "/v1/chat/completions" and .state == "open")' "$log")
      test "$(printf '%s\n' "$opened" | wc -l)" -eq 1
      printf '%s' "$opened" | jq -e '.request.messages[0].content == "SYSMARK"' > /dev/null
      test "$(printf '%s' "$opened" | jq -r '.id')" = "$(printf '%s' "$record" | jq -r '.id')"

      printf '%s' "$record" | jq -e '.request.messages[0].content == "SYSMARK"' > /dev/null
      printf '%s' "$record" | jq -e '.request.tools[0].function.name == "TOOLMARK"' > /dev/null
      printf '%s' "$record" | jq -e '.status == 200' > /dev/null

      # The rendered prompt must come from the payload that was forwarded, not
      # from anything the proxy kept on its own side.
      printf '%s' "$record" | jq -e '.prompt | test("TOOLMARK") and test("SYSMARK") and test("USERMARK")' > /dev/null

      # The cross-check that makes the prompt trustworthy: the proxy's token
      # count and the upstream's prompt_tokens have to be the same number.
      reported=$(grep -o '"prompt_tokens":[0-9]*' "$sse" | head -1 | cut -d: -f2)
      counted=$(printf '%s' "$record" | jq -r '.promptTokens')
      test "$counted" = "$reported"
      echo "  prompt tokens: proxy $counted == upstream $reported"

      # Secrets do not belong in a transcript that exists to be pasted around.
      printf '%s' "$record" | jq -e '.requestHeaders.authorization == "<redacted>"' > /dev/null
      ! grep SECRET "$log" > /dev/null

      # The stream reached the client whole, chunk framing intact.
      grep 'data: \[DONE\]' "$sse" > /dev/null
      test "$(grep '^data: {' "$sse" | cut -c7- | jq -rs 'map(select(.choices)) | map(.choices[0].delta.content) | add')" = "hello"

      # The reader splits the same exchange back into its parts — every message
      # by role, not just the last, so the system prompt is visible.
      shown=$(llama-wiretap-show "$log")
      printf '%s' "$shown" | grep -- "1. SYSTEM" > /dev/null
      printf '%s' "$shown" | grep "SYSMARK" > /dev/null
      printf '%s' "$shown" | grep "USERMARK" > /dev/null

      # The whole thread in order, with the tool call and its result visible
      # rather than rendered as empty content.
      printf '%s' "$shown" | grep "2. USER" > /dev/null
      printf '%s' "$shown" | grep "3. ASSISTANT" > /dev/null
      printf '%s' "$shown" | grep -- "→ TOOLMARK" > /dev/null
      printf '%s' "$shown" | grep "TOOLARGMARK" > /dev/null
      printf '%s' "$shown" | grep "4. TOOL RESULT (call_1)" > /dev/null
      printf '%s' "$shown" | grep "TOOLRESULTMARK" > /dev/null
      printf '%s' "$shown" | grep "5. USER" > /dev/null
      printf '%s' "$shown" | grep "FOLLOWUPMARK" > /dev/null
      printf '%s' "$shown" | grep -- "── TOOLS ──" > /dev/null
      printf '%s' "$shown" | grep "TOOLMARK" > /dev/null
      printf '%s' "$shown" | grep -- "── THINKING ──" > /dev/null
      printf '%s' "$shown" | grep "thinking out loud" > /dev/null
      printf '%s' "$shown" | grep -- "── ANSWER ──" > /dev/null
      printf '%s' "$shown" | grep "hello" > /dev/null
      llama-wiretap-show "$log" --list | grep "done 200" > /dev/null

      # --rendered is the literal templated string plus the reply, and it drops
      # the structured thread the string already contains inline.
      rendered=$(llama-wiretap-show "$log" --rendered)
      printf '%s' "$rendered" | grep -- "── RENDERED PROMPT" > /dev/null
      printf '%s' "$rendered" | grep "im_start" > /dev/null
      printf '%s' "$rendered" | grep "TOOLMARK" > /dev/null
      printf '%s' "$rendered" | grep "SYSMARK" > /dev/null
      printf '%s' "$rendered" | grep "thinking out loud" > /dev/null
      printf '%s' "$rendered" | grep "hello" > /dev/null
      ! printf '%s' "$rendered" | grep -- "1. SYSTEM" > /dev/null

      # --full keeps both views side by side.
      full=$(llama-wiretap-show "$log" --full)
      printf '%s' "$full" | grep -- "1. SYSTEM" > /dev/null
      printf '%s' "$full" | grep -- "4. TOOL RESULT (call_1)" > /dev/null
      printf '%s' "$full" | grep -- "── RENDERED PROMPT" > /dev/null
      printf '%s' "$full" | grep "im_start" > /dev/null
      printf '%s' "$full" | grep -- "── THINKING ──" > /dev/null
      printf '%s' "$full" | grep "thinking out loud" > /dev/null
      printf '%s' "$full" | grep -- "── ANSWER ──" > /dev/null
      printf '%s' "$full" | grep "hello" > /dev/null

      # --all walks every exchange, including the readiness probe, so a whole
      # conversation reads in one pass.
      all=$(llama-wiretap-show "$log" --all --rendered)
      test "$(printf '%s\n' "$all" | grep -c "^exchange ")" -ge 1
      printf '%s' "$all" | grep -- "── ANSWER ──" > /dev/null
    }

    # One exchange over one topology, from a cold listener to a checked
    # transcript. $1 names the leg, $2 is the proxy's --listen, $3 the base URL
    # to reach it, and anything after that extra curl arguments.
    exercise() {
      leg="$1"
      listen="$2"
      url="$3"
      shift 3

      llama-wiretap --listen "$listen" --upstream "$upstream" --log "$leg.jsonl" & pids="$pids $!"
      if [ "''${listen%.sock}" != "$listen" ]; then
        wait_for_path "$listen"
        # The socket is as sensitive as the transcript behind it.
        test "$(stat -c %a "$listen")" = "600"
      fi
      wait_for_http "$@" "$url/apply-template" -d '{}'

      # A request carrying no messages is still proxied and still logged, but
      # there is no chat template to render, so it carries no prompt.
      wait_for_record "$leg.jsonl" /apply-template
      jq -e 'select(.path == "/apply-template" and .state == "done") | has("prompt") | not' "$leg.jsonl" > /dev/null

      curl -sS --max-time 10 "$@" "$url/v1/chat/completions" \
        -H 'content-type: application/json' -H 'authorization: Bearer SECRET' \
        -d "$request" > "$leg.sse"
      wait_for_record "$leg.jsonl" /v1/chat/completions
      assert_transcript "$leg.jsonl" "$leg.sse"
      echo "  ✓ $leg"
    }

    # pi's own session format, which the reader also has to speak: different
    # records, content as typed blocks, and no proxy involved at all.
    echo "=== pi session file ==="
    cat > session.jsonl <<'SESSION'
{"type":"session","version":3,"id":"sess-1","cwd":"/tmp/project"}
{"type":"model_change","provider":"llama-cpp","modelId":"MODELMARK"}
{"type":"message","message":{"role":"user","content":"SESSIONUSERMARK"}}
{"type":"message","message":{"role":"assistant","content":[{"type":"thinking","thinking":"SESSIONTHINKMARK"},{"type":"toolCall","id":"c1","name":"SESSIONTOOLMARK","arguments":{"p":1}},{"type":"text","text":"SESSIONANSWERMARK"}]}}
{"type":"message","message":{"role":"toolResult","toolCallId":"c1","toolName":"SESSIONTOOLMARK","content":[{"type":"text","text":"SESSIONRESULTMARK"}]}}
SESSION
    session=$(llama-wiretap-show session.jsonl)
    printf '%s' "$session" | grep "sess-1" > /dev/null
    printf '%s' "$session" | grep "MODELMARK" > /dev/null
    printf '%s' "$session" | grep "SESSIONUSERMARK" > /dev/null
    printf '%s' "$session" | grep -- "2. THINKING" > /dev/null
    printf '%s' "$session" | grep "SESSIONTHINKMARK" > /dev/null
    printf '%s' "$session" | grep "SESSIONANSWERMARK" > /dev/null
    printf '%s' "$session" | grep -- "→ SESSIONTOOLMARK" > /dev/null
    printf '%s' "$session" | grep "TOOL RESULT (SESSIONTOOLMARK)" > /dev/null
    printf '%s' "$session" | grep "SESSIONRESULTMARK" > /dev/null
    # It has to say what it cannot show, rather than imply pi sent no system prompt.
    printf '%s' "$session" | grep "no system prompt" > /dev/null
    # Piped output carries no escape codes.
    ! printf '%s' "$session" | grep -q "$(printf '\033')" 
    echo "  ✓ pi session"

    echo "=== TCP upstream ==="
    node ${./test-upstream.mjs} 127.0.0.1:18081 & pids="$pids $!"
    wait_for_http http://127.0.0.1:18081/apply-template -d '{}'
    upstream=127.0.0.1:18081

    exercise tcp-tcp 127.0.0.1:18082 http://127.0.0.1:18082
    exercise uds-tcp "$work/uds-tcp.sock" http://localhost --unix-socket "$work/uds-tcp.sock"

    echo "=== Unix socket upstream ==="
    node ${./test-upstream.mjs} "$work/upstream.sock" & pids="$pids $!"
    wait_for_path "$work/upstream.sock"
    upstream="$work/upstream.sock"

    exercise uds-uds "$work/uds-uds.sock" http://localhost --unix-socket "$work/uds-uds.sock"
    exercise tcp-uds 127.0.0.1:18083 http://127.0.0.1:18083

    # The transcripts stay in the build log: they carry timestamps and the
    # builder's temporary directory, and copying them into $out would make an
    # otherwise reproducible derivation differ on every run.
    mkdir -p $out
    echo "all four listener/upstream transport combinations proxied and logged" > $out/result
  '';
}
