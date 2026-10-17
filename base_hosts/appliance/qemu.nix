{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./guest.nix
  ];
  # The development guest's flake-copy helper needs Home Manager.
  disabledModules = [ "${inputs.self}/modules/current_system_flake.nix" ];

  virtualisation = {
    graphics = true;
    writableStoreUseTmpfs = false;
  };
  hardware.graphics.enable = true;
}
