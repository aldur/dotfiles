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
  jsonFormat = pkgs.formats.json { };
  cfg = config.programs.claude-code;

  # Helper: merge a Nix-generated JSON file into an existing file at activation.
  # Existing keys are preserved; Nix-managed keys take precedence on conflict.
  # We use `cat f.tmp > f` instead of `mv f.tmp f` so that this plays nicely
  # with persistance.
  mergeJsonActivation = name: target: source: ''
    if [ -s "${target}" ]; then
      $DRY_RUN_CMD ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "${target}" ${source} > "${target}.tmp"
      $DRY_RUN_CMD cat "${target}.tmp" > "${target}"
      rm -f "${target}.tmp"
    else
      $DRY_RUN_CMD install -Dm644 ${source} "${target}"
    fi
  '';

  claudeSettingsSchema = pkgs.fetchurl {
    url = "https://json.schemastore.org/claude-code-settings.json";
    hash = "sha256-UBqmJ3D3gfA9s0TUlVavSe7Nn52T+SA/KPcZM6eoc4Q=";
  };

  claude-statusline = pkgs.callPackage ../../packages/claude-statusline { };

  claudeSettings = jsonFormat.generate "claude-code-settings.json" cfg.writableSettings;

  claudeSettingsValidated =
    pkgs.runCommand "validate-claude-settings"
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      ''
        check-jsonschema --schemafile ${claudeSettingsSchema} ${claudeSettings}
        touch $out
      '';

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

    # Write settings and MCP config as writable files (not read-only symlinks).
    # The native claude binary from ~/.local/bin bypasses the Nix wrapper,
    # so MCP servers must be configured via ~/.claude.json directly.
    home.activation.claudeSettings = lib.mkIf enabled (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Validated at build time by ${claudeSettingsValidated}
        $DRY_RUN_CMD mkdir -p "$HOME/.claude"
        ${mergeJsonActivation "settings" "$HOME/.claude/settings.json" claudeSettings}
        ${mergeJsonActivation "mcp" "$HOME/.claude.json" claudeMcpConfig}
      ''
    );

    home.shellAliases = lib.optionalAttrs enabled {
      claude-yolo =
        let
          needsPathPrefix = if pkgs.stdenv.isDarwin then true else osConfig.programs.nix-ld.enable;
          pathPrefix = lib.optionalString needsPathPrefix "PATH=~/.local/bin/:$PATH ";
        in
        "${pathPrefix}IS_SANDBOX=1 CLAUBBIT=1 DISABLE_TELEMETRY=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --dangerously-skip-permissions";
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
