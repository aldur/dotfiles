{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  osConfig,
  ...
}:
let
  enabled = osConfig.programs.aldur.claude-code.enable;
  sandboxCfg = osConfig.programs.aldur.claude-code.sandbox;
  sandbox = sandboxCfg.enable;
  runtimeAllowlist = sandboxCfg.extraRuntimeDirAllowlist;
  jsonFormat = pkgs.formats.json { };
  cfg = config.programs.claude-code;

  # Substrings identifying hook commands we manage. The merge filter below
  # strips matcher-entries whose hook command contains one of these substrings
  # before re-adding our entries, so:
  #   - hooks contributed by other modules are preserved untouched
  #   - dropping a hook from Nix removes it on next activation
  #   - Nix store path churn doesn't accumulate duplicates
  # Substring match is used because writeShellScript paths include a content
  # hash (e.g. /nix/store/HASH-claude-tmux-silence) that changes on every
  # rebuild. Keep substrings specific enough to avoid false positives.
  nixManagedHookMarkers = [ "claude-tmux-silence" ];

  # jq filter: deep-merge objects, but for `.hooks.<event>` arrays strip any
  # existing entries whose hook command contains a Nix-managed marker, then
  # concatenate. No-op for files without `.hooks`.
  hooksAwareMerge = ''
    def is_managed:
      (.hooks // []) | any(
        (.command // "") as $c
        | any($managed[]; . as $m | $c | contains($m))
      );
    def strip_managed(h):
      (h // {})
      | with_entries(.value |= map(select(is_managed | not)))
      | with_entries(select(.value | length > 0));
    def merge_hooks($a; $b):
      (($a | keys) + ($b | keys) | unique) as $ks
      | reduce $ks[] as $k ({}; .[$k] = (($a[$k] // []) + ($b[$k] // [])));
    .[0] as $e | .[1] as $n
    | ($e * $n)
    | (strip_managed($e.hooks)) as $eh
    | (merge_hooks($eh; ($n.hooks // {}))) as $merged
    | if $merged == {} then del(.hooks) else .hooks = $merged end
  '';

  # Helper: merge a Nix-generated JSON file into an existing file at activation.
  # Existing keys are preserved; Nix-managed keys take precedence on conflict.
  # We use `cat f.tmp > f` instead of `mv f.tmp f` so that this plays nicely
  # with persistance.
  mergeJsonActivation = name: target: source: ''
    if [ -s "${target}" ]; then
      $DRY_RUN_CMD ${lib.getExe pkgs.jq} \
        --argjson managed ${lib.escapeShellArg (builtins.toJSON nixManagedHookMarkers)} \
        -s ${lib.escapeShellArg hooksAwareMerge} \
        "${target}" ${source} > "${target}.tmp"
      $DRY_RUN_CMD cat "${target}.tmp" > "${target}"
      rm -f "${target}.tmp"
    else
      $DRY_RUN_CMD install -Dm644 ${source} "${target}"
    fi
  '';

  claude-statusline = pkgs.callPackage ../../packages/claude-statusline { };

  # Pre-accept the workspace trust dialog for $PWD so trust-gated features
  # (e.g. statusLine) render under `claude-yolo`. Uses cat-to-overwrite so the
  # underlying inode is preserved (impermanence bind-mounts ~/.claude.json).
  claude-trust-cwd = pkgs.writeShellScript "claude-trust-cwd" ''
    set -euo pipefail
    config="$HOME/.claude.json"
    [ -s "$config" ] || exit 0
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    ${lib.getExe pkgs.jq} --arg cwd "$PWD" \
      '.projects[$cwd].hasTrustDialogAccepted = true' "$config" > "$tmp"
    cat "$tmp" > "$config"
  '';

  # Shadow the user's tmux server, ssh-agent socket from subprocesses Claude
  # spawns under YOLO. Filesystem and network pass through so editing, nix
  # builds, and the Claude API still work. CLAUDE_NO_SANDBOX=1 skips the wrapper.
  claude-bwrap = pkgs.writeShellScript "claude-bwrap" ''
    set -euo pipefail

    if [ "''${CLAUDE_NO_SANDBOX:-0}" = "1" ]; then
      exec "$@"
    fi

    uid=$(${pkgs.coreutils}/bin/id -u)
    runtime="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"

    # Spawn xdg-dbus-proxy: filtered view of the session bus. Closes the
    # systemd-run / StartTransientUnit escape, which would otherwise let
    # the sandboxed Claude spawn arbitrary commands as a transient user
    # unit (outside the bwrap, with full access to every shadowed path).
    bus_addr="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime/bus}"
    proxy_sock=$(${pkgs.coreutils}/bin/mktemp -u /tmp/claude-dbus-proxy.XXXXXX)
    ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy "$bus_addr" "$proxy_sock" --filter \
      --talk=org.freedesktop.DBus \
      ${
        lib.concatMapStringsSep " \\\n      " (n: "--talk=${lib.escapeShellArg n}") sandboxCfg.extraDbusTalk
      } &
    proxy_pid=$!
    trap 'kill "$proxy_pid" 2>/dev/null; rm -f "$proxy_sock"' EXIT
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      [ -S "$proxy_sock" ] && break
      sleep 0.1
    done
    [ -S "$proxy_sock" ] || { echo "claude-bwrap: xdg-dbus-proxy did not come up" >&2; exit 1; }

    # Simple `bwrap` invocation that shadows `runtime`, the `tmux`/`ssh` sockets, 
    # and hides pid/ipc/uts. 
    #
    # WARNING: Doesn't try to be bullet-proof.
    args=(
      --dev-bind / /
      --proc /proc
      --tmpfs "$runtime"
      --tmpfs "/tmp/tmux-$uid"
      --tmpfs "$HOME/.ssh"
      --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
      --tmpfs "$HOME/.config/nix"
      --ro-bind-try "$HOME/.config/systemd" "$HOME/.config/systemd"
      --ro-bind-try "$HOME/.config/fish" "$HOME/.config/fish"
      --ro-bind-try "$HOME/.local/bin" "$HOME/.local/bin"
      --ro-bind-try "$data_home/lazyvim" "$data_home/lazyvim"
      --unsetenv TMUX
      --unsetenv TMUX_PANE
      --unsetenv TMUX_TMPDIR
      --unsetenv SSH_AUTH_SOCK
      --unsetenv SSH_AGENT_PID
      --unsetenv GNUPGHOME
      --unsetenv GPG_TTY
      --die-with-parent
      --unshare-pid
      --unshare-ipc
      --unshare-uts
    )

    # Re-bind allowlist into the empty runtime tmpfs. The list is the
    # value of programs.aldur.claude-code.sandbox.extraRuntimeDirAllowlist.
    # The session bus is handled separately below via xdg-dbus-proxy.
    for entry in ${lib.concatMapStringsSep " " lib.escapeShellArg runtimeAllowlist}; do
      src="/run/user/$uid/$entry"
      [ -e "$src" ] && args+=(--bind "$src" "$runtime/$entry")
    done

    # Bind the filtered bus and point DBUS_SESSION_BUS_ADDRESS at it.
    args+=(
      --bind "$proxy_sock" "$runtime/bus"
      --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$runtime/bus"
    )

    # Shell history files.
    for f in "$data_home/fish/fish_history" \
             "$HOME/.bash_history"; do
      [ -f "$f" ] && args+=(--bind /dev/null "$f")
    done

    # Not exec'd so the EXIT trap can clean up the proxy.
    ${pkgs.bubblewrap}/bin/bwrap "''${args[@]}" -- "$@"
  '';

  claudeSettings = jsonFormat.generate "claude-code-settings.json" cfg.writableSettings;

  claudeMcpConfig = jsonFormat.generate "claude-mcp.json" {
    mcpServers = {
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
        args = [ "--headless" ];
      };
    };
  };
in
{
  options.programs.claude-code.writableSettings = lib.mkOption {
    inherit (jsonFormat) type;
    default = { };
    description = ''
      Settings merged into ~/.claude/settings.json as a writable file
      (not a read-only symlink). Any module can contribute to this option
      and the module system deep-merges all contributions.

      Do NOT use the upstream `programs.claude-code.settings` option — it
      creates a read-only symlink that claude-code cannot write to at runtime.
    '';
  };

  config = {
    programs.claude-code = lib.optionalAttrs enabled {
      inherit (osConfig.programs.aldur.claude-code) enable;
      package = pkgsUnstable.claude-code;

      writableSettings = {
        "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        theme = "dark";
        skipDangerousModePermissionPrompt = true;
        statusLine = {
          type = "command";
          command = "${claude-statusline}/bin/claude-statusline";
        };
      };

      skillsDir = "${
        pkgs.fetchFromGitHub {
          owner = "anthropics";
          repo = "skills";
          rev = "7029232b9212482c0476da354b83364bd28fab2f";
          hash = "sha256-rQXOcZk0nF9ZqYK0CUelGoY4oj/gYZgcdh1qUdwvx2k=";
        }
      }/skills";
    };

    home = {
      # Write settings and MCP config as writable files (not read-only symlinks).
      # The native claude binary from ~/.local/bin bypasses the Nix wrapper,
      # so MCP servers must be configured via ~/.claude.json directly.
      activation.claudeSettings = lib.mkIf enabled (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p "$HOME/.claude"
          ${mergeJsonActivation "settings" "$HOME/.claude/settings.json" claudeSettings}
          ${mergeJsonActivation "mcp" "$HOME/.claude.json" claudeMcpConfig}
        ''
      );

      # Re-create ~/.local/bin/claude symlink after an impermanence wipe by
      # pointing it at the highest version under ~/.local/share/claude/versions/.
      # No-op on first boot (before claude-code has installed itself).
      activation.claudeSymlink = lib.mkIf enabled (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          versionsDir="$HOME/.local/share/claude/versions"
          if [ -d "$versionsDir" ]; then
            latest=$(ls -v "$versionsDir" 2>/dev/null | tail -n1 || true)
            if [ -n "''${latest:-}" ]; then
              $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
              $DRY_RUN_CMD ln -sfn "$versionsDir/$latest" "$HOME/.local/bin/claude"
            fi
          fi
        ''
      );

      shellAliases = lib.optionalAttrs enabled {
        claude-yolo =
          let
            needsPathPrefix = if pkgs.stdenv.isDarwin then true else osConfig.programs.nix-ld.enable;
            pathPrefix = lib.optionalString needsPathPrefix "PATH=~/.local/bin/:$PATH ";
            sandboxPrefix = lib.optionalString (sandbox && pkgs.stdenv.isLinux) "${claude-bwrap} ";
          in
          "${pathPrefix}${claude-trust-cwd}; IS_SANDBOX=1 CLAUBBIT=1 DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ${sandboxPrefix}claude --dangerously-skip-permissions";
      };
    };

    # The upstream HM module creates a read-only symlink for settings.json when
    # `programs.claude-code.settings` is non-empty, which conflicts with our
    # activation-based merge that keeps the file writable (claude-code writes to it
    # at runtime). Catch this early so the conflict doesn't silently swallow settings.
    assertions = lib.mkIf enabled [
      {
        assertion = cfg.settings == { };
        message = ''
          Do not set `programs.claude-code.settings` directly — it creates a
          read-only symlink that conflicts with the activation-based writable
          settings.json. Use `programs.claude-code.writableSettings` instead.
        '';
      }
    ];
  };
}
