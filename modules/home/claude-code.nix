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
  jsonFormat = pkgs.formats.json { };
  cfg = config.programs.claude-code;

  inherit (cfg) nixManagedHookMarkers;

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
  #
  # Branch on DRY_RUN instead of prefixing with the deprecated $DRY_RUN_CMD:
  # the redirections would still run under `home-manager switch -n` and
  # truncate the live target with the echoed command text.
  mergeJsonActivation = name: target: source: ''
    if [[ -v DRY_RUN ]]; then
      echo "Would merge ${name} from ${source} into ${target}"
    elif [ -s "${target}" ]; then
      ${lib.getExe pkgs.jq} \
        --argjson managed ${lib.escapeShellArg (builtins.toJSON nixManagedHookMarkers)} \
        -s ${lib.escapeShellArg hooksAwareMerge} \
        "${target}" ${source} > "${target}.tmp"
      cat "${target}.tmp" > "${target}"
      rm -f "${target}.tmp"
      chmod 600 "${target}"
    else
      # Write through, no replace: with impermanence, the target is a
      # bind mount, empty on the first boot. A replace fails on it.
      mkdir -p "$(dirname "${target}")"
      cat ${source} > "${target}"
      chmod 600 "${target}"
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

  needsPathPrefix =
    if pkgs.stdenv.hostPlatform.isDarwin then true else osConfig.programs.nix-ld.enable;
  # `claude-yolo` runs claude with nonessential traffic off. The env below:
  # IS_SANDBOX lets `--dangerously-skip-permissions` run as root.
  # CLAUBBIT skips the trust, MCP, and CLAUDE.md dialogs.
  # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC also turns off telemetry,
  # the feature flag fetch, and the auto-updater. Remote Control needs
  # the flag fetch, so it stays off. It also skips the bootstrap request
  # that lists the models of the account, so claude only sees the models
  # cached in ~/.claude.json. The wrapper refreshes that cache with one
  # short run without the variable when the claude version changed or
  # the last refresh is older than a week. `claude -p /model` does the
  # startup fetch and exits with no inference call, in about a second.
  # A failed refresh never blocks the launch.
  claude-yolo = import ./yolo-script.nix { inherit pkgs lib config; } {
    agent = "claude";
    describe = "Run claude in the sandbox, with no permission prompts and no nonessential traffic";
    inherit sandbox;
    flags = {
      refresh = "Refresh the model list before the launch";
      online = "Keep the sandbox, but let nonessential traffic through (Remote Control works)";
    };
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${lib.optionalString needsPathPrefix ''export PATH="$HOME/.local/bin:$PATH"''}
      stamp="$HOME/.claude/yolo-refresh"
      max_age=$((7 * 24 * 3600))

      refresh_due() {
        local version now last_version="" last_at=""
        version=$(claude --version 2>/dev/null | cut -d' ' -f1) || return 1
        [ -n "$version" ] || return 1
        now=$(date +%s)
        if [ "''${argc_refresh:-0}" -eq 0 ] && [ -r "$stamp" ]; then
          read -r last_version last_at < "$stamp" || true
          [ "$last_version" = "$version" ] && [ $((now - ''${last_at:-0})) -lt "$max_age" ] && return 1
        fi
        echo "$version $now" > "$stamp.next"
      }

      # The refresh skips project hooks and MCP servers: it only needs the
      # startup fetch.
      if [ "''${argc_online:-0}" -eq 0 ] && refresh_due; then
        echo "claude-yolo: refreshing the model list" >&2
        if env -u CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -u DISABLE_TELEMETRY \
          DISABLE_AUTOUPDATER=1 timeout 15 "''${sandbox[@]}" claude \
          -p /model --strict-mcp-config --settings '{"disableAllHooks":true}' >/dev/null 2>&1; then
          mv "$stamp.next" "$stamp"
        else
          rm -f "$stamp.next"
          echo "claude-yolo: model list refresh failed, using the cached list" >&2
        fi
      fi

      ${claude-trust-cwd}
      export IS_SANDBOX=1 CLAUBBIT=1
      if [ "''${argc_online:-0}" -eq 1 ]; then
        unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY
      else
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      fi
      exec "''${sandbox[@]}" claude --dangerously-skip-permissions "$@"
    '';
  };

  claudeSettings = jsonFormat.generate "claude-code-settings.json" cfg.writableSettings;

  claudeMcpConfig = jsonFormat.generate "claude-mcp.json" {
    mcpServers = {
      playwright = {
        command = lib.getExe pkgs.playwright-mcp;
        args = [
          "--headless"
          "--isolated"
        ];
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

  options.programs.claude-code.nixManagedHookMarkers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Substrings identifying hook commands wired via Nix. On activation,
      any entry in ~/.claude/settings.json whose hook command contains one
      of these substrings is stripped before the Nix-generated entries are
      merged in, so:
        - hooks contributed by other modules are preserved untouched
        - dropping a hook from Nix removes it on next activation
        - Nix store path churn doesn't accumulate duplicates
      Substring match is used because writeShellScript paths include a
      content hash that changes on every rebuild. Hosts wiring their own
      hooks via `writableSettings.hooks` should contribute the relevant
      substrings here so their stale generations get reclaimed.
    '';
  };

  config = {
    programs.claude-code = lib.optionalAttrs enabled {
      inherit (osConfig.programs.aldur.claude-code) enable;
      package = pkgsUnstable.claude-code;

      writableSettings = {
        "$schema" = "https://json.schemastore.org/claude-code-settings.json";
        theme = "dark";
        tui = "default";
        skipDangerousModePermissionPrompt = true;
        # Retain session transcripts effectively forever. Claude Code prunes
        # JSONL logs older than `cleanupPeriodDays` (default 30) at startup, and
        # there is no infinite sentinel — so set a 100-year horizon.
        cleanupPeriodDays = 36500;
        statusLine = {
          type = "command";
          command = "${claude-statusline}/bin/claude-statusline";
        };
        # These apply to every `claude` invocation, sandboxed or not.
        env = {
          # Skip the "How is Claude doing this session?" surveys.
          CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
          # Clone plugin marketplaces over HTTPS. This stops the
          # `ssh -T git@github.com` probe that a fresh install makes.
          # https://github.com/anthropics/claude-code/issues/21108
          CLAUDE_CODE_PLUGIN_PREFER_HTTPS = "1";
        };
      };

      nixManagedHookMarkers = [ "claude-tmux-silence" ];
    };

    home = {
      # NOTE: `home.file` instead of `skills` to enable cross-platform evaluation used in checks.
      file = lib.mkIf enabled {
        "${cfg.configDir}/skills".source = "${pkgs.claude-skills}/skills";
      };

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

      packages = lib.optionals enabled [ claude-yolo ];
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
