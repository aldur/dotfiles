{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.baguette-guest
    ./guest.nix
  ];
  hardening.foreignKernel = true;
  hardware.graphics.enable = false;
  virtualisation = {
    buildMemorySize = 4096;
    diskImageSize = 8192;
  };
}
