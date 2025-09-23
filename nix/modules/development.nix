{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  claudeCfg = config.programs.aldur.claude-code;

  # CLI utils useful for development.
  basePackages = with pkgs; [
    autossh
    bat
    difftastic
    ripgrep-all
    universal-ctags
    watch
  ];
  extraPackages = (lib.optionals claudeCfg.enable [ pkgs.claude-code ]) ++ [ pkgs.gemini-cli ];
in
{
  imports = [
    ./cli.nix
    ./nixpkgs.nix
  ];

  options.programs.aldur.claude-code = {
    enable = mkEnableOption "claude-code";
  };

  config = {
    environment.systemPackages = basePackages ++ extraPackages;
    nixpkgs.allowUnfreeByName = mkIf claudeCfg.enable [ "claude-code" ];
  };
}
