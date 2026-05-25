# NixOS-specific home-manager configuration
{ config, osConfig, ... }:
{
  imports = [
    ../home/home.nix
  ];

  home.homeDirectory = "/home/${config.home.username}";
  services.gpg-agent.pinentry.package = osConfig.programs.gnupg.agent.pinentryPackage;
}
