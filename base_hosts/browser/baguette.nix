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
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
  users.users.${config.mainUser}.extraGroups = [ "audio" ];
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce (
    lib.getExe config.programs.firefox.finalPackage
  );
}
