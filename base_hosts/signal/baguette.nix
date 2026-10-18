{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    "${inputs.self}/base_hosts/appliance/baguette.nix"
    ./guest.nix
  ];
  # The session can start before maitred writes the host DNS configuration.
  systemd.tmpfiles.rules = [ "f /run/resolv.conf 0644 root root -" ];
  networking.hostName = "signal-baguette";
  crostini.sommelier.xwayland.enable = false;
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce "${pkgs.coreutils}/bin/false";
}
