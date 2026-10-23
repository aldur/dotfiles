{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.pi;
  dotfilesSkills = import ../../skills;
  jsonType = (pkgs.formats.json { }).type;
  managedConfig = pkgs.writeText "pi-managed-config.json" (
    builtins.toJSON { inherit (cfg) settings keybindings; }
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
    configSync = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Synchronize the declared Pi settings and keybindings.";
    };
    evalHarness = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Eval harness that runs pi with the home files of this module.";
      default = import ./eval-harness.nix { inherit pkgs lib; } {
        name = "pi";
        inherit (pkgs.pi-coding-agent) version;
        home = {
          ".pi/agent" = pkgs.runCommand "pi-eval-agent-config" { } ''
            mkdir "$out"
            ${lib.getExe pkgs.pi.configSync} ${managedConfig} "$out"
          '';
          ".pi/agent/AGENTS.md" = ./agents/AGENTS.md;
        }
        // lib.mapAttrs' (name: lib.nameValuePair ".pi/agent/skills/${name}") dotfilesSkills;
        credentials = [ ".pi/agent/auth.json" ];
        sessionDirs = [ ".pi/agent/sessions" ];
        # No self-updates: the run must use the pinned pi.
        command = ''
          exec ${lib.getExe (pkgs.pi.override { selfUpdates = false; })} -p --mode json \
            --model "$model" ''${effort:+--thinking "$effort"} "$prompt"
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
    };
  };

  config = {
    programs.pi = {
      # Keep terminal/tmux scrollback with Pi 1.0's regular UI mode.
      settings.tuiMode = lib.mkDefault "regular";

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
        lib.mapAttrs' (
          name: source:
          lib.nameValuePair ".pi/agent/skills/${name}" {
            inherit source;
            recursive = true;
          }
        ) dotfilesSkills
      );

      # Both Home Manager and the container call this explicit helper. Running
      # after linkGeneration lets HM retire its former keybindings symlink first.
      activation.piSettings = lib.mkIf cfg.enable (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run ${lib.getExe cfg.configSync}
        ''
      );
    };
  };
}
