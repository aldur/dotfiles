# The flake outputs of one `qemu-vm` guest (see base_hosts/qemu and
# base_hosts/autofirma). They are a launcher package for each host system
# and a nixosConfiguration for each guest architecture. The
# nixosConfiguration lets the guest rebuild its image from inside.
# flake.nix exports this function as `lib.mkQemuGuest`.
{
  self,
  nixpkgs,
  flake-utils,
}:
{
  # The inputs of the guest flake. mkSpecialArgs merges them with ours.
  inputs,
  # Attribute name of the launcher package.
  name,
  # Hostname of the guest. It also names the nixosConfigurations, because
  # `nixos-rebuild` inside the VM selects its configuration by hostname.
  hostName,
  # NixOS module with what runs in the guest. It must import
  # `nixosModules.qemu-guest`.
  qemuModule,
  # Arguments for `qemu-vm.override`, for example defaultMemory.
  vmOverrides ? { },
}:
let
  specialArgs = self.lib.mkSpecialArgs inputs;

  hostSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  perHostSystem = flake-utils.lib.eachSystem hostSystems (system: {
    packages = {
      ${name} = self.legacyPackages.${system}.qemu-vm.override (
        vmOverrides
        // {
          inherit qemuModule;
          # The guest module can read the inputs of the guest flake. The
          # dotfiles package only knows the dotfiles inputs.
          inherit (specialArgs) inputs;
        }
      );
      default = perHostSystem.packages.${system}.${name};
    };
  });

  guest =
    system:
    nixpkgs.lib.nixosSystem {
      inherit specialArgs system;
      modules = self.legacyPackages.${system}.qemu-vm.modules ++ [ qemuModule ];
    };
in
perHostSystem
// {
  nixosConfigurations = {
    ${hostName} = guest "aarch64-linux";
    "${hostName}-aarch64" = guest "aarch64-linux";
    "${hostName}-x86_64" = guest "x86_64-linux";
  };
}
