{
  pkgs,
  homeFiles,
  homeProfile,
  piConfigSync,
}:
uid:
pkgs.writeShellApplication {
  name = "pi-container";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.socat
  ];
  text = ''
    socket=/var/host-services/llama.sock
    if (( $# == 0 )) || [[ "$1" == -* ]]; then set -- pi-yolo "$@"; fi
    if [ "$(id -u)" = 0 ]; then
      if [ -S "$socket" ] && [ ! -L "$socket" ]; then
        chown -h ${toString uid}:100 "$socket"
      fi
      exec chroot --userspec=${toString uid}:100 --groups=100 --skip-chdir / "$0" "$@"
    fi

    # A fresh tmpfs home needs the same configuration as the image. Keep
    # existing user files; only seed a home without its profile link.
    if [ ! -e "$HOME/.nix-profile" ]; then
      cp -a --no-clobber --no-preserve=ownership,mode ${homeFiles}/. "$HOME/"
      ln -s ${homeProfile} "$HOME/.nix-profile"
    fi

    # An unmounted /workspace belongs to the image and may be read-only.
    # Use the writable home for scratch work, preserving explicit mounts and
    # custom working directories. Read mountinfo directly to catch bind mounts
    # on the same filesystem without adding a mount utility to the image.
    if [[ "$PWD" == /workspace ]]; then
      workspace_mounted=0
      while read -r _ _ _ _ mount_path _; do
        if [[ "$mount_path" == /workspace ]]; then
          workspace_mounted=1
          break
        fi
      done < /proc/self/mountinfo
      if (( ! workspace_mounted )); then
        mkdir -p "$HOME/workspace"
        cd "$HOME/workspace"
      fi
    fi

    # Apply the same managed configuration as Home Manager, including to an
    # existing home. Undeclared settings and keybindings are preserved.
    ${pkgs.lib.getExe piConfigSync}

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
    if [[ "$1" == pi-yolo ]] && [ -t 0 ] && [ -t 1 ]; then
      # Reuse the session created by the shared tmux configuration. Quote
      # each argument for its shell, including literal quotes and newlines.
      printf -v pi_command "'%s' " "''${@//\'/\'\\\'\'}"
      # Keep startup errors visible instead of discarding the failed pane.
      # A normal Pi exit still closes it.
      exec tmux start-server \; set-option -p remain-on-exit failed \; \
        respawn-pane -k "exec $pi_command" \; attach-session
    fi
    exec "$@"
  '';
}
