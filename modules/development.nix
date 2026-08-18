{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  claudeCfg = config.programs.aldur.claude-code;
  devCfg = config.programs.aldur.development;

  # CLI utils useful for development.
  basePackages =
    with pkgs;
    [
      ripgrep-all
    ]
    ++ lib.optional devCfg.difftastic.enable difftastic # Enable saving ~120M.
    ++ lib.optionals config.programs.aldur.workstation.enable [
      universal-ctags
      watch
    ];
in
{
  imports = [
    ./cli.nix
    ./nixpkgs.nix
  ];

  options.programs.aldur = {
    claude-code = {
      enable = mkEnableOption "claude-code";
      sandbox = {
        enable = mkOption {
          type = types.bool;
          default = pkgs.stdenv.hostPlatform.isLinux;
          description = ''
            On Linux, wrap claude-yolo in bubblewrap to shadow `tmux` and `ssh`
            sockets, providing _a layer of defense_ against a rogue `claude-code`
            instance. Doesn't prevent persistance (which should be prevented 
            through additional layers, e.g. impermanence).

            Set CLAUDE_NO_SANDBOX=1 in the environment to bypass for a single
            invocation without rebuilding.
          '';
        };
        extraRuntimeDirAllowlist = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "docker.sock"
            "podman/podman.sock"
          ];
          description = ''
            Entries under $XDG_RUNTIME_DIR to bind into the sandbox (path
            relative to $XDG_RUNTIME_DIR). Declare host-specific sockets or dirs
            that `claude` needs.

            Be careful: some entries will allow sandbox escape.
          '';
        };
        extraDbusTalk = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "org.freedesktop.Notifications" ];
          description = ''
            Additional bus names the sandboxed Claude is allowed to TALK to
            via the session bus, on top of the always-on org.freedesktop.DBus
            (which is required for any client's initial Hello() handshake).
          '';
        };
      };
    };

    codex.enable = mkEnableOption "codex";

    # Interactive-workstation comforts: atuin, clipshare, difftastic, spare
    # dev CLIs. A headless or agent guest sets this to false and keeps only
    # the essentials.
    workstation.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install interactive-workstation comforts.";
    };

    development.difftastic.enable = mkOption {
      type = types.bool;
      default = config.programs.aldur.workstation.enable;
      defaultText = lib.literalExpression "config.programs.aldur.workstation.enable";
      description = "Install difftastic (and keep the `gd` git aliases working).";
    };
  };

  config = {
    environment.systemPackages = basePackages;
    nixpkgs.allowUnfreeByName = mkIf claudeCfg.enable [ "claude-code" ];
  };
}
