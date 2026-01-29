{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  name = "aws-cli";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "AWS CLI with SSM support";
  };

  imports = [
    ./nixpkgs.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.allowUnfreeByName = [ "ssm-session-manager-plugin" ];

    home-manager.users.aldur =
      { config, ... }: # home-manager's config, not the OS one
      {
        programs.awscli.enable = true;
      };

    environment.systemPackages = with pkgs; [
      awscli2
      ssm-session-manager-plugin
    ];

  };
}
