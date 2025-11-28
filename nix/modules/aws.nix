{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
with lib;
let
  name = "aws-cli";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "AWS CLI and SSM";
  };

  imports = [
    ./nixpkgs.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.allowUnfreeByName = [ "ssm-session-manager-plugin" ];

    home-manager.users.aldur =
      { config, ... }: # home-manager's config, not the OS one
      {
        imports = [ inputs.agenix.homeManagerModules.default ];
      };

    environment.systemPackages = with pkgs; [
      awscli2
      ssm-session-manager-plugin
    ];

  };
}
