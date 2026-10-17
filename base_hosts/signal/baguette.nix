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
  # Message contents must not appear in ChromeOS notifications. URL opening
  # stays disabled in this appliance, including garcon's host URL handler.
  systemd.user.services.cros-notificationd.enable = false;
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce "${pkgs.coreutils}/bin/false";
  systemd.services.cros-port-listener.enable = false;
}
