{ pkgs }:
pkgs.writeShellApplication {
  name = "pi-model-relay";
  runtimeInputs = [ pkgs.socat ];
  text = ''
    socket="''${LLAMA_SOCKET_PATH:-/var/host-services/llama.sock}"
    if [[ -z "''${LLAMA_SOCKET_PATH:-}" && ! -S "$socket" ]]; then
      exec "$@"
    fi
    [[ -S "$socket" ]] || { echo "inference socket missing: $socket" >&2; exit 1; }
    socat -u /dev/null "UNIX-CONNECT:$socket"
    socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork "UNIX-CONNECT:$socket" &
    relay=$!
    child=
    # shellcheck disable=SC2329 # Called by the EXIT trap.
    cleanup() {
      kill "$relay" ''${child:+"$child"} 2>/dev/null || true
      wait "$relay" ''${child:+"$child"} 2>/dev/null || true
    }
    trap 'cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    socat -u /dev/null TCP4:127.0.0.1:8080,retry=50,interval=0.02
    kill -0 "$relay"
    export LLAMA_BASE_URL=http://127.0.0.1:8080/v1
    "$@" <&0 &
    child=$!
    status=0
    wait "$child" || status=$?
    exit "$status"
  '';
}
