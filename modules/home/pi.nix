{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.pi;
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
