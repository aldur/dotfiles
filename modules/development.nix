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

  sandboxOptions = import ./home/agent-sandbox/options.nix { inherit lib pkgs; };

  # CLI utils useful for development.
  basePackages =
    with pkgs;
    lib.optional devCfg.difftastic.enable difftastic # Enable saving ~120M.
    ++ lib.optionals config.programs.aldur.workstation.enable [
      ripgrep-all # ~350M with pandoc
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
      sandbox = sandboxOptions "claude-yolo";
    };

    codex = {
      enable = mkEnableOption "codex";
      sandbox = sandboxOptions "codex-yolo";
    };

    # Interactive-workstation comforts: atuin, clipshare, difftastic, spare
    # dev CLIs, the custom tools of modules/home/home.nix. A headless or
    # agent guest sets this to false and keeps only the essentials.
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
