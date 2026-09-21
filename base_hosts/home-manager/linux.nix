# User-level integration for Ubuntu and other non-NixOS Linux hosts.
{
  config,
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
    # genericLinux exposes the profile's terminfo to systemd services only.
    # SSH shells need the same search path through Home Manager's shell setup.
    sessionVariables.TERMINFO_DIRS = lib.mkDefault config.systemd.user.sessionVariables.TERMINFO_DIRS;
    sessionPath = [
      "$HOME/.local/bin"
      # Fish does not source the multi-user installer's /etc/profile.d script.
      "/nix/var/nix/profiles/default/bin"
    ];
  };
  programs.aldur.lazyvim.enable = lib.mkDefault true;
  programs.better-nix-search.enable = lib.mkDefault true;
  services.gpg-agent.pinentry.package = lib.mkDefault pkgs.pinentry-curses;
  systemd.user.startServices = "sd-switch";
}
