# NixOS-specific home-manager configuration
{ config, ... }: {
  imports = [ ../home/home.nix ];
  home.homeDirectory = "/home/${config.home.username}";
}
