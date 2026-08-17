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
      # The sampling knobs print with the exchange.
      printf '%s' "$shown" | grep -- "model m · stream true" > /dev/null
      # The accounting from the stream: latency, size, speed, finish reason.
      printf '%s' "$shown" | grep -E "(ms|[0-9]s) · 7 completion tokens · 42.5 tok/s · finish stop" > /dev/null
      # The model's tool call, reassembled from its streamed fragments.
      printf '%s' "$shown" | grep -F -- '→ STREAMTOOLMARK({"x":1})' > /dev/null
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

    echo "=== prefix breaks are visible ==="
    # Wait until the log holds $2 completed chat exchanges.
    wait_for_chats() {
      for _ in $(seq 1 100); do
        n=$(jq -c 'select(.path == "/v1/chat/completions" and .state == "done")' "$1" | grep -c . || true)
        if [ "$n" -ge "$2" ]; then return 0; fi
        sleep 0.1
      done
      echo "timed out waiting for $2 completed chats in $1" >&2
      exit 1
    }

    # A good turn appends to the thread. The prompts then share their prefix,
    # up to the re-rendered turn tail. The turn also carries template kwargs,
    # the spelling pi-llama uses for the thinking knobs.
    followup=$(jq -c '.messages += [{"role":"assistant","content":"hello"},{"role":"user","content":"NEXTMARK"}] | .chat_template_kwargs = {reasoning_effort: "medium"}' <<< "$request")
    # An edited system prompt diverges at the top. Every cached token after
    # that point is lost. The model also changes, so the break comes with a
    # template swap for the audit to name.
    broken=$(jq -c '.messages[0].content = "MUTATEDSYSMARK" | .model = "m2"' <<< "$followup")

    curl -sS --max-time 10 http://127.0.0.1:18083/v1/chat/completions \
      -H 'content-type: application/json' -d "$followup" > /dev/null
    wait_for_chats tcp-uds.jsonl 2
    curl -sS --max-time 10 http://127.0.0.1:18083/v1/chat/completions \
      -H 'content-type: application/json' -d "$broken" > /dev/null
    wait_for_chats tcp-uds.jsonl 3

    audit=$(llama-wiretap-show tcp-uds.jsonl --prefix)
    printf '%s' "$audit" | grep "keeps the prefix" > /dev/null
    printf '%s' "$audit" | grep "breaks the prefix" > /dev/null
    # The divergence snippet names the edit itself.
    printf '%s' "$audit" | grep "MUTATEDSYSMARK" > /dev/null
    printf '%s' "$audit" | grep "1 prefix break" > /dev/null
    # The break came with a model swap; the audit says so.
    printf '%s' "$audit" | grep -- "template changed here: m -> m2" > /dev/null

    llama-wiretap-show tcp-uds.jsonl --list | grep "prefix kept" > /dev/null
    llama-wiretap-show tcp-uds.jsonl --list | grep "prefix broke @" > /dev/null
    echo "  ✓ prefix audit"

    echo "=== the template travels with the transcript ==="
    # Three chat exchanges, two models: one snapshot per template, not per
    # exchange.
    test "$(jq -r 'select(.state == "template") | .model' tcp-uds.jsonl | paste -sd, -)" = "m,m2"
    # The snapshot stamps the llama.cpp build, for the drift reports.
    test "$(jq -r 'select(.state == "template") | .buildInfo' tcp-uds.jsonl | sort -u)" = "b0-test"
    # The reader assigns each exchange the template in effect for it.
    tpl=$(llama-wiretap-show tcp-uds.jsonl --template)
    printf '%s' "$tpl" | grep -- "── CHAT TEMPLATE" > /dev/null
    printf '%s' "$tpl" | grep "TEMPLATEMARK-m2" > /dev/null
    llama-wiretap-show tcp-uds.jsonl --template --id 2 | grep "TEMPLATEMARK-m " > /dev/null
    echo "  ✓ template snapshot"

    # The template kwargs print as a knob on their exchange.
    llama-wiretap-show tcp-uds.jsonl --id 3 | grep 'chat_template_kwargs {"reasoning_effort":"medium"}' > /dev/null
    echo "  ✓ knobs"

    echo "=== a failed render says so ==="
    cat > render-error.jsonl <<'RENDERR'
{"id":1,"at":"2026-08-17T12:00:00.000Z","state":"open","method":"POST","path":"/v1/chat/completions","request":{"messages":[{"role":"user","content":"hi"}]}}
{"id":1,"at":"2026-08-17T12:00:01.000Z","state":"done","method":"POST","path":"/v1/chat/completions","status":200,"request":{"messages":[{"role":"user","content":"hi"}]},"response":"data: [DONE]\n\n","renderError":"Error: ECONNREFUSED"}
RENDERR
    llama-wiretap-show render-error.jsonl | grep "prompt render failed" | grep ECONNREFUSED > /dev/null
    echo "  ✓ render error"

    echo "=== --tokens re-tokenizes against a live server ==="
    # Through the proxy on purpose: /tokenize is passthrough traffic, and the
    # exchange it logs must not disturb the analyses above.
    toks=$(llama-wiretap-show tcp-uds.jsonl --tokens --id 2 --server 127.0.0.1:18083)
    printf '%s' "$toks" | grep "re-tokenized against 127.0.0.1:18083" > /dev/null
    printf '%s' "$toks" | grep "SYSMARK" > /dev/null
    printf '%s' "$toks" | grep "matches the capture" > /dev/null
    ! printf '%s' "$toks" | grep -q "drifted"
    # The server target also takes the upstream's socket, or a pasted URL.
    llama-wiretap-show tcp-uds.jsonl --tokens --id 2 --server "$upstream" \
      | grep "matches the capture" > /dev/null
    llama-wiretap-show tcp-uds.jsonl --tokens --id 2 --server "http://127.0.0.1:18083/v1" \
      | grep "matches the capture" > /dev/null
    echo "  ✓ tokens"

    # The transcripts stay in the build log: they carry timestamps and the
    # builder's temporary directory, and copying them into $out would make an
    # otherwise reproducible derivation differ on every run.
    mkdir -p $out
    echo "all four listener/upstream transport combinations proxied and logged" > $out/result
  '';
}
