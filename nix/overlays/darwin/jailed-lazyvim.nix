{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:
(
  final: prev:
  let
    lazyvim = prev.callPackage ../../packages/lazyvim/lazyvim.nix { inherit inputs pkgs pkgsUnstable; };
    name = "lazyvim";
    sandboxProfile = ../../../osx/sandboxes/lazyvim.sb;
  in
  {
    jailed-lazyvim = prev.writeShellApplication {
      inherit name;

      runtimeInputs = [
        lazyvim."${name}"
      ];

      # Jail nvim
      text = ''
        EXTRA_DIR=""
        ARGS=()

        while [[ $# -gt 0 ]]; do
          case "$1" in
            --allow-dir)
              if [[ -z "''${2:-}" ]]; then
                echo "Error: --allow-dir requires a directory argument" >&2
                exit 1
              fi
              EXTRA_DIR="$(cd "$2" 2>/dev/null && pwd)" || {
                echo "Error: directory '$2' does not exist or is not accessible" >&2
                exit 1
              }
              shift 2
              ;;
            *)
              ARGS+=("$1")
              shift
              ;;
          esac
        done

        PROFILE="${sandboxProfile}"

        if [[ -n "$EXTRA_DIR" ]]; then
          printf '\033[1;33mWARNING:\033[0m Sandbox write access extended to: \033[1;31m%s\033[0m\n' "$EXTRA_DIR" >&2
          printf 'Continue? [y/N] ' >&2
          read -r response
          case "$response" in
            [yY])
              ;;
            *)
              echo "Aborted." >&2
              exit 1
              ;;
          esac

          PROFILE="$(mktemp)"
          trap 'rm -f "$PROFILE"' EXIT
          {
            cat "${sandboxProfile}"
            printf '\n; Extra writable directory (dynamic)\n(allow file-write* (subpath "%s"))\n' "$EXTRA_DIR"
          } > "$PROFILE"
        fi

        sandbox-exec -f "$PROFILE" ${name} ''${ARGS[@]+"''${ARGS[@]}"}
      '';
    };
  }
)
