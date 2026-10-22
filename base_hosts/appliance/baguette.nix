{
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.nixos-crostini.nixosModules.baguette
    ./guest.nix
  ];
  hardening.foreignKernel = true;
  users.users.${config.mainUser}.crostini.enable = true;
  baguette = {
    imageCompression = {
      level = 19;
      threads = 4;
    };
    ephemeralRoot = {
      enable = true;
      tmpfsSize = "1G";
      mountOptions = [ "nosuid" "nodev" ];
    };
    portListener.enable = false;
    notifications.enable = false;
  };
  crostini.extraTools.enable = false;
  hardware.graphics.enable = false;
  virtualisation = {
    buildMemorySize = 4096;
    # The base has a fixed size. ChromeOS expands the separate state disk.
    diskImageSize = 4096;
  };
}
