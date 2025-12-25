{
  description = "A QEMU NixOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../../..?dir=nix";
      url = "github:aldur/dotfiles?dir=nix";
    };
  };
  outputs =
    { aldur-dotfiles, ... }:
    let
      inherit (aldur-dotfiles) specialArgs;
    in
    aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages = rec {
        vm-nogui = aldur-dotfiles.legacyPackages.${system}.qemu-vm.override { qemuModule = ./qemu.nix; };
        default = vm-nogui;
      };
    })
    // (
      let
        cfg =
          targetSystem:
          aldur-dotfiles.inputs.nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            modules = aldur-dotfiles.legacyPackages.${targetSystem}.qemu-vm.modules ++ [ ./qemu.nix ];
            system = targetSystem;
          };

        qemu-nixos-aarch64 = cfg "aarch64-linux";
        qemu-nixos-x86_64 = cfg "x86_64-linux";

      in
      {
        nixosConfigurations = {
          qemu-nixos = qemu-nixos-aarch64;
          inherit qemu-nixos-aarch64 qemu-nixos-x86_64;
        };
      }
    );
}
