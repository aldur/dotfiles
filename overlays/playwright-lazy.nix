{
  writeShellApplication,
  runCommand,
  coreutils,
  findutils,
  flock,
  nix,
  runtimeShell,
  browserExpression,
}:
let
  launcher = writeShellApplication {
    name = "playwright-browser";
    runtimeInputs = [
      coreutils
      findutils
      flock
      nix
    ];
    text = ''
      umask 077
      state="''${PLAYWRIGHT_BROWSER_STATE_DIR:-''${XDG_CACHE_HOME:-$HOME/.cache}/playwright-nix}"
      root="$state/${builtins.baseNameOf browserExpression}/browser"
      mkdir -p "$(dirname "$root")"
      # Descriptors 3 and 4 carry Playwright's browser protocol.
      exec 9>"$root.lock"
      flock 9
      if [ ! -e "$root" ]; then
        echo "Installing pinned Chromium with Nix. The first launch can take several minutes." >&2
        if ! nix-build --extra-experimental-features flakes ${browserExpression} --out-link "$root" >&2; then
          echo "Chromium installation failed. Check Nix/network access, then retry or run playwright-browser-prefetch." >&2
          exit 1
        fi
      fi
      browser=$(find -L "$root" -type f \( -name chrome-headless-shell -o -name headless_shell \
        -o -path '*/Contents/MacOS/Chromium' -o -path '*/Contents/MacOS/Google Chrome for Testing' \) -print -quit)
      if [ -z "$browser" ] || [ ! -x "$browser" ]; then
        echo "No Chromium executable in $root" >&2
        exit 1
      fi
      exec 9>&-
      if [ "''${1:-}" = --prefetch ]; then
        printf '%s\n' "$browser"
        exit 0
      fi
      exec "$browser" "$@"
    '';
  };
in
runCommand "playwright-browser-launcher" { } ''
  mkdir -p "$out/bin"
  ln -s ${launcher}/bin/playwright-browser "$out/bin/playwright-browser"
  cat > "$out/bin/playwright-browser-prefetch" <<'EOF'
  #!${runtimeShell}
  if [ "$#" -ne 0 ]; then
    echo 'Usage: playwright-browser-prefetch' >&2
    [ "$#" -eq 1 ] && [ "$1" = --help ] && exit 0
    exit 1
  fi
  exec ${launcher}/bin/playwright-browser --prefetch
  EOF
  chmod +x "$out/bin/playwright-browser-prefetch"
''
