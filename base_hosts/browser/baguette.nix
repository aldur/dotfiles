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
  # Keep graphics access and allow the user to open /dev/wl0.
  users.users.${config.mainUser}.extraGroups = lib.mkForce [
    "video"
    "render"
    "virtwl"
  ];
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce (
    lib.getExe config.programs.firefox.finalPackage
  );
}
