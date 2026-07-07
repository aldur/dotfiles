#!/usr/bin/env bash
# Functional tests for faraday. Run as a NON-ROOT user (root masks
# permission bugs, e.g. the loopback-bringup EPERM):
#
#   nix shell .#faraday nixpkgs#socat -c packages/faraday/test.sh
#
# Needs: faraday on PATH (override with $FARADAY), socat for the stub
# HTTP server.
set -uo pipefail

FARADAY=${FARADAY:-faraday}

[ "$(id -u)" -ne 0 ] || {
  echo "run as a non-root user" >&2
  exit 1
}
command -v "$FARADAY" >/dev/null || {
  echo "faraday not on PATH" >&2
  exit 1
}
command -v socat >/dev/null || {
  echo "socat (stub server) not on PATH" >&2
  exit 1
}

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  echo "ok   - $1"
}
bad() {
  fail=$((fail + 1))
  echo "FAIL - $1"
}
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
check_not() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi
}

# --- stub HTTP server on the host -------------------------------------------
# The response lives in a file: socat's SYSTEM: address mangles embedded
# quotes, so an inline printf would get word-split.
PORT=$((20000 + RANDOM % 20000))
RESPONSE_FILE=$(mktemp)
printf 'HTTP/1.0 200 OK\r\ncontent-length: 2\r\n\r\nok' >"$RESPONSE_FILE"
socat "TCP-LISTEN:$PORT,bind=127.0.0.1,fork,reuseaddr" \
  "SYSTEM:cat $RESPONSE_FILE" 2>/dev/null &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -f "$RESPONSE_FILE"' EXIT
for _ in $(seq 1 50); do
  timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null && break
  sleep 0.1
done

# --- 1. allowed destination reachable through the relay ---------------------
# (also proves loopback works with no manual bringup)
response=$("$FARADAY" --allow "127.0.0.1:$PORT" -- bash -c \
  "exec 3<>/dev/tcp/127.0.0.1/$PORT && printf 'GET / HTTP/1.0\r\n\r\n' >&3 && head -n1 <&3" 2>/dev/null)
case $response in
*"200 OK"*) ok "allowed destination returns 200 through the relay" ;;
*) bad "allowed destination returns 200 through the relay (got: $response)" ;;
esac

# --- 2. everything else is blocked -------------------------------------------
check_not "unrelated destination is blocked" \
  timeout 5 "$FARADAY" --allow "127.0.0.1:$PORT" -- bash -c 'exec 3<>/dev/tcp/8.8.8.8/443'
check_not "host loopback is unreachable without --allow" \
  timeout 5 "$FARADAY" -- bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT"

# --- 3. only lo exists in the sandbox (/proc/net/dev, not /sys) --------------
ifaces=$("$FARADAY" -- cat /proc/net/dev 2>/dev/null | tail -n +3 | cut -d: -f1 | tr -d ' ')
if [ "$ifaces" = "lo" ]; then
  ok "/proc/net/dev shows only lo"
else
  bad "/proc/net/dev shows only lo (got: $ifaces)"
fi

# --- 4. writable-path policy --------------------------------------------------
rwdir=$(mktemp -d)
check "--rw path is writable" \
  "$FARADAY" --rw "$rwdir" -- bash -c "echo hi >'$rwdir/probe'"
canary="$HOME/.faraday-test-canary.$$"
check_not "\$HOME is read-only by default" \
  "$FARADAY" -- bash -c "echo hi >'$canary'"
rm -f "$canary" # in case the test failed
check "sandbox /tmp is writable (tmpfs)" \
  "$FARADAY" -- bash -c "echo hi >/tmp/probe.$$"
check_not "sandbox /tmp does not leak to the host" test -e "/tmp/probe.$$"
check "--writable-home makes \$HOME writable" \
  "$FARADAY" --writable-home -- bash -c "echo hi >'$canary' && rm '$canary'"
maskdir=$(mktemp -d)
touch "$maskdir/secret"
masked=$("$FARADAY" --mask "$maskdir" -- ls "$maskdir" 2>/dev/null)
if [ -z "$masked" ]; then
  ok "--mask hides directory contents"
else
  bad "--mask hides directory contents (saw: $masked)"
fi
check_not "--mask wins over --rw" \
  "$FARADAY" --rw "$maskdir" --mask "$maskdir" -- test -e "$maskdir/secret"
check "--mask skips missing paths" \
  "$FARADAY" --mask /nonexistent/faraday-test -- true
rm -rf "$rwdir" "$maskdir"

# --- 5. exit codes propagate ---------------------------------------------------
status=0
"$FARADAY" -- bash -c 'exit 42' 2>/dev/null || status=$?
if [ "$status" -eq 42 ]; then ok "exit code propagates (offline path)"; else bad "exit code propagates (offline path, got $status)"; fi
status=0
"$FARADAY" --allow "127.0.0.1:$PORT" -- bash -c 'exit 7' 2>/dev/null || status=$?
if [ "$status" -eq 7 ]; then ok "exit code propagates (relay path)"; else bad "exit code propagates (relay path, got $status)"; fi

# --- 6. --map / name resolution ------------------------------------------------
check "--map adds the host to /etc/hosts" \
  "$FARADAY" --allow "127.0.0.1:$PORT" --map faraday-test.internal -- \
  grep -q "127.0.0.1.*faraday-test.internal" /etc/hosts
mapped=$("$FARADAY" --allow "127.0.0.1:$PORT" --map faraday-test.internal -- \
  getent hosts faraday-test.internal 2>/dev/null | awk '{print $1}')
if [ "$mapped" = "127.0.0.1" ]; then
  ok "--map name resolves to 127.0.0.1 (nscd bypassed)"
else
  bad "--map name resolves to 127.0.0.1 (got: $mapped)"
fi
check_not "no host-side DNS through the nscd socket" \
  timeout 5 "$FARADAY" -- getent hosts nixos.org

# --- 7. argument validation ----------------------------------------------------
check_not "rejects malformed --allow" "$FARADAY" --allow nonsense -- true
check_not "rejects bad port" "$FARADAY" --allow 127.0.0.1:99999 -- true
check_not "rejects missing command" "$FARADAY" --allow "127.0.0.1:$PORT"
check_not "rejects unreachable destination" \
  timeout 10 "$FARADAY" --allow 127.0.0.1:1 -- true
check_not "rejects duplicate in-sandbox ports" \
  "$FARADAY" --allow "127.0.0.1:$PORT" --allow "localhost:$PORT" -- true

# --- 8. clean teardown -----------------------------------------------------------
relay_pattern="UNIX-LISTEN:${TMPDIR:-/tmp}/faraday\."
inner_relay_pattern="UNIX-CONNECT:${TMPDIR:-/tmp}/faraday\."
"$FARADAY" --allow "127.0.0.1:$PORT" -- true 2>/dev/null
sleep 0.5
check_not "no leftover host relay after normal exit" pgrep -f "$relay_pattern"
check_not "no leftover in-sandbox relay after normal exit" pgrep -f "$inner_relay_pattern"
check_not "no leftover socket dir after normal exit" \
  compgen -G "${TMPDIR:-/tmp}/faraday.*"

# Ctrl-C: setsid makes the wrapper a process-group leader, so kill -INT
# -PID mimics the terminal signalling the whole foreground group.
setsid "$FARADAY" --allow "127.0.0.1:$PORT" -- sleep 30 2>/dev/null &
wrapper=$!
sleep 2
kill -INT -"$wrapper" 2>/dev/null
wait "$wrapper" 2>/dev/null
sleep 0.5
check_not "no leftover relay after Ctrl-C" pgrep -f "$relay_pattern"
check_not "no leftover in-sandbox relay after Ctrl-C" pgrep -f "$inner_relay_pattern"
check_not "no leftover socket dir after Ctrl-C" \
  compgen -G "${TMPDIR:-/tmp}/faraday.*"

# SIGTERM to the wrapper alone must tear down the sandboxed command too.
"$FARADAY" --allow "127.0.0.1:$PORT" -- sleep 31536 2>/dev/null &
wrapper=$!
sleep 2
kill -TERM "$wrapper"
wait "$wrapper" 2>/dev/null
sleep 0.5
check_not "no leftover relay after SIGTERM" pgrep -f "$relay_pattern"
check_not "no leftover in-sandbox relay after SIGTERM" pgrep -f "$inner_relay_pattern"
check_not "sandboxed command is gone after SIGTERM" pgrep -f "^sleep 31536$"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
