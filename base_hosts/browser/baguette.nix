{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    "${inputs.self}/base_hosts/appliance/baguette.nix"
    ./guest.nix
  ];
  networking.hostName = "browser-baguette";
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce (
    lib.getExe config.programs.firefox.finalPackage
  );
}
