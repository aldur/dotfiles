# User-level integration for Ubuntu and other non-NixOS Linux hosts.
{
  pkgs,
  lib,
  ...
}:
let
  packages = import ../../modules/shared/environment.nix {
    inherit pkgs lib;
  };
in
{
  imports = [ ../../modules/nixpkgs.nix ];

  targets.genericLinux.enable = true;
  # This is a terminal environment; GPU integration requires separate host setup.
  targets.genericLinux.gpu.enable = lib.mkDefault false;

  home = {
    packages = packages.cli ++ packages.terminfo;
    sessionPath = [ "$HOME/.local/bin" ];
  };
  programs.aldur.lazyvim.enable = lib.mkDefault true;
  services.gpg-agent.pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  systemd.user.startServices = "sd-switch";
}
