{
  config,
  pkgs,
  pkgsUnstable,
  lib,
  ...
}:
with lib;
let
  claudeCfg = config.programs.aldur.claude-code;
  geminiCfg = config.programs.aldur.gemini-cli;

  # CLI utils useful for development.
  basePackages = with pkgs; [
    autossh
    bat
    difftastic
    ripgrep-all
    universal-ctags
    watch
  ];
  extraPackages =
    (lib.optionals claudeCfg.enable [ pkgsUnstable.claude-code ])
    ++ (lib.optionals geminiCfg.enable [ pkgs.gemini-cli ]);
in
{
  imports = [
    ./cli.nix
    ./nixpkgs.nix
  ];

  options.programs.aldur.claude-code = {
    enable = mkEnableOption "claude-code";
  };

  options.programs.aldur.gemini-cli = {
    enable = mkEnableOption "gemini-cli";
  };

  config = {
    environment.systemPackages = basePackages ++ extraPackages;
    nixpkgs.allowUnfreeByName = mkIf claudeCfg.enable [ "claude-code" ];
  };
}
