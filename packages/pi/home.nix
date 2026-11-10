{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.pi;
  dotfilesSkills = pkgs.pi.skills;
  jsonType = (pkgs.formats.json { }).type;
  managedConfig = pkgs.writeText "pi-managed-config.json" (
    builtins.toJSON { inherit (cfg) settings keybindings mcp; }
  );
in
{
  options.programs.pi = {
    enable = lib.mkEnableOption "the pi coding agent with its plugins";
    settings = lib.mkOption {
      type = jsonType;
      default = { };
      description = ''
        Nix-managed keys in Pi's writable settings.json. Declared values win
        on activation and container startup; other keys are preserved.
        Removing a declaration leaves its last value in the file.
      '';
    };
    keybindings = lib.mkOption {
      type = jsonType;
      default = { };
      description = ''
        Nix-managed keys in Pi's writable keybindings.json, merged with the
        same ownership rules as programs.pi.settings. Shortcut arrays replace.
      '';
    };
    mcp = lib.mkOption {
      type = jsonType;
      default = { };
      description = "Nix-managed keys in Pi's writable mcp.json. Other keys are preserved.";
    };
    configSync = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Synchronize the declared Pi settings, keybindings, and MCP servers.";
    };
    evalHarnesses = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      internal = true;
      description = ''
        Eval harnesses that run pi: `pi` with the plugins and home files of
        this module, `pi-bare` with none of them.
      '';
      default =
        let
          mk =
            bare:
            import ../../modules/home/eval-harness.nix { inherit pkgs lib; } {
              name = if bare then "pi-bare" else "pi";
              inherit (pkgs.pi-coding-agent) version;
              home = lib.optionalAttrs (!bare) (
                {
                  ".pi/agent" = pkgs.runCommand "pi-eval-agent-config" { } ''
                    mkdir "$out"
                    ${lib.getExe pkgs.pi.configSync} ${managedConfig} "$out"
                  '';
                  ".pi/agent/AGENTS.md" = ../../modules/home/agents/AGENTS.md;
                }
                // lib.mapAttrs' (name: lib.nameValuePair ".pi/agent/skills/${name}") dotfilesSkills
              );
              credentials = [ ".pi/agent/auth.json" ];
              sessionDirs = [ ".pi/agent/sessions" ];
              effortLevels = [
                "off"
                "minimal"
                "low"
                "medium"
                "high"
                "xhigh"
                "max"
              ];
              # No self-updates: the run must use the pinned pi. The bare pi has
              # no plugins.
              command = ''
                export PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1
                exec ${
                  if bare then
                    lib.getExe pkgs.pi-coding-agent
                  else
                    lib.getExe (pkgs.pi.override { selfUpdates = false; })
                } -p --mode json \
                  --model "$model" ''${effort:+--thinking "$effort"} "$prompt"
              '';
              progress = ''
                if .type == "tool_execution_start" then
                  "\(.toolName): \(.args.command // .args.path // .args.file_path // .args.pattern // "")"
                elif .type == "message_end" and .message.role == "assistant" then
                  .message.content[] | select(.type == "text") | .text
                else empty end
              '';
              usage = ''
                map(select(.type == "message_end" and .message.role == "assistant") | .message) as $msgs
                | ($msgs | map(.usage)) as $u
                | {
                    input_tokens: ($u | map(.input) | add),
                    cache_read_tokens: ($u | map(.cacheRead) | add),
                    cache_write_tokens: ($u | map(.cacheWrite) | add),
                    output_tokens: ($u | map(.output) | add),
                    reasoning_tokens: null,
                    cost_usd: ($u | map(.cost.total) | add),
                    models: ($msgs | map(.provider + "/" + (.responseModel // .model)) | unique | if . == [] then null else . end)
                  }
              '';
            };
        in
        {
          pi = mk false;
          pi-bare = mk true;
        };
    };
  };

  config = {
    programs.pi = {
      mcp.mcpServers.playwright-lazy = lib.mkIf pkgs.pi.browserEnabled {
        command = lib.getExe (pkgs.callPackage ./browser.nix { });
        exposure = "codemode";
        timeout = 660;
        description = "Browse web and publication pages with isolated Chromium: navigate, follow links, read page snapshots, capture screenshots, and download PDFs. Files are saved in a separate .pi/browser directory for each worker; tool results give readable paths.";
      };
      # Keep terminal/tmux scrollback with Pi 1.0's regular UI mode.
      settings.tuiMode = lib.mkDefault "regular";
      settings.quietStartup = lib.mkDefault false;

      keybindings = lib.mkDefault {
        # Move within the prompt, then browse history.
        "tui.editor.cursorUp" = [
          "up"
          "ctrl+p"
        ];
        "tui.editor.cursorDown" = [
          "down"
          "ctrl+n"
        ];
        "tui.select.up" = [
          "up"
          "ctrl+p"
        ];
        "tui.select.down" = [
          "down"
          "ctrl+n"
        ];
        "app.session.togglePath" = [ "ctrl+alt+p" ];
        "app.session.toggleNamedFilter" = [ "ctrl+alt+n" ];
        "app.models.toggleProvider" = [ "ctrl+alt+p" ];
        "app.model.cycleForward" = [ ];
      };

      configSync = pkgs.writeShellScriptBin "pi-sync-managed-config" ''
        exec ${lib.getExe pkgs.pi.configSync} ${managedConfig} "$HOME/.pi/agent"
      '';
    };

    home = {
      packages = lib.optionals cfg.enable [ pkgs.pi ];

      # Share the same skill files as Codex and Claude, including Pi-only hosts.
      file = lib.mkIf cfg.enable (
        { ".pi/agent/.home-manager".text = ""; }
        // lib.mapAttrs' (
          name: source:
          lib.nameValuePair ".pi/agent/skills/${name}" {
            inherit source;
            recursive = true;
          }
        ) dotfilesSkills
      );

      # Both Home Manager and the container call this explicit helper.
      activation.piSettings = lib.mkIf cfg.enable (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run ${lib.getExe cfg.configSync}
        ''
      );
    };
  };
}
