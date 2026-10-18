# ChromeOS supplies the window integration and kernel.
{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.self.nixosModules.baguette-guest
    ./guest.nix
  ];

  networking.hostName = "browser-baguette";
  hardening.foreignKernel = true;
  hardware.graphics.enable = false;
  # Merge with guest.nix's forced group list so the user can open /dev/wl0.
  users.users.${config.mainUser}.extraGroups = lib.mkForce [ "virtwl" ];
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce (
    lib.getExe config.programs.firefox.finalPackage
  );

  virtualisation = {
    buildMemorySize = 4096;
    diskImageSize = 8192;
  };
}
