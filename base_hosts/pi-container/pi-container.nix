{ pkgs }:
uid:
pkgs.writeShellApplication {
  name = "pi-container";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.socat
  ];
  text = ''
    socket=/var/host-services/llama.sock
    if (( $# == 0 )); then set -- pi-yolo; fi
    if [ "$(id -u)" = 0 ]; then
      if [ -S "$socket" ] && [ ! -L "$socket" ]; then
        chown -h ${toString uid}:100 "$socket"
      fi
      exec chroot --userspec=${toString uid}:100 --groups=100 --skip-chdir / "$0" "$@"
    fi

    export PATH="/bin:/run/current-system/sw/bin:$PATH"
    if [[ -n "''${LLAMA_SOCKET_PATH:-}" || -S "$socket" ]]; then
      [[ -S "$socket" ]] || { echo "inference socket missing: $socket" >&2; exit 1; }
      # Make sure that you can access the socket. Start one relay for this container.
      socat -u /dev/null "UNIX-CONNECT:$socket"
      socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork "UNIX-CONNECT:$socket" &
      relay=$!
      socat -u /dev/null TCP4:127.0.0.1:8080,retry=50,interval=0.02
      kill -0 "$relay"
      export LLAMA_BASE_URL=http://127.0.0.1:8080/v1
    fi
    exec "$@"
  '';
}
