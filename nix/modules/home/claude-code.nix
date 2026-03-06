{
  pkgs,
  pkgsUnstable,
  lib,
  osConfig,
  ...
}:
let
  enabled = osConfig.programs.aldur.claude-code.enable;
  jsonFormat = pkgs.formats.json { };

  # Helper: merge a Nix-generated JSON file into an existing file at activation.
  # Existing keys are preserved; Nix-managed keys take precedence on conflict.
  mergeJsonActivation = name: target: source: ''
    if [ -f "${target}" ]; then
      $DRY_RUN_CMD ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "${target}" ${source} > "${target}.tmp"
      $DRY_RUN_CMD mv "${target}.tmp" "${target}"
    else
      $DRY_RUN_CMD install -Dm644 ${source} "${target}"
    fi
  '';

  claudeSettingsSchema = pkgs.fetchurl {
    url = "https://json.schemastore.org/claude-code-settings.json";
    hash = "sha256-5ps7X94iYKsvCGqgQXTvtQRCgwev8Ff7RgIt+CMduBo=";
  };

  claude-statusline = pkgs.callPackage ../../packages/claude-statusline { };

  claudeSettingsValue = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    theme = "dark";
    skipDangerousModePermissionPrompt = true;
    statusLine = {
      type = "command";
      command = "${claude-statusline}/bin/claude-statusline";
    };
  };

  claudeSettings = jsonFormat.generate "claude-code-settings.json" claudeSettingsValue;

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
  programs.claude-code = lib.optionalAttrs enabled {
    inherit (osConfig.programs.aldur.claude-code) enable;
    package = pkgsUnstable.claude-code;

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
        pathPrefix = lib.optionalString osConfig.programs.nix-ld.enable "PATH=~/.local/bin/:$PATH ";
      in
      "${pathPrefix}IS_SANDBOX=1 CLAUBBIT=1 DISABLE_TELEMETRY=1 claude --dangerously-skip-permissions";
  };

  # Work around claude-code using SSH URLs for its plugins repo.
  # https://github.com/anthropics/claude-code/issues/21108
  programs.git.settings = lib.mkIf enabled {
    url."https://github.com/anthropics/".insteadOf = "ssh://git@github.com/anthropics/";
  };
}
