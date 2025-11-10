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
      targetSystem = "aarch64-linux";
      inherit (aldur-dotfiles) specialArgs;
    in
    aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages = rec {
        vm-nogui = aldur-dotfiles.outputs.utils.${system}.qemu-vm;
        default = vm-nogui;
      };
    })
    // {
      nixosConfigurations.qemu-nixos = aldur-dotfiles.inputs.nixpkgs.lib.nixosSystem {
        inherit specialArgs;
        inherit (aldur-dotfiles.outputs.utils.${targetSystem}.qemu-vm) modules;
        system = targetSystem;
      };
    };
}
