{
  description = "A persistent Firefox VM for ChromeOS Baguette and QEMU.";

  inputs = {
    aldur-dotfiles.url = "github:aldur/dotfiles";
    nixos-crostini = {
      url = "github:aldur/nixos-crostini";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };

  outputs =
    { aldur-dotfiles, nixos-crostini, ... }@inputs:
    let
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;
      qemu = aldur-dotfiles.lib.mkQemuGuest {
        inherit inputs;
        name = "browser-vm";
        hostName = "browser-vm";
        qemuModule = ./desktop.nix;
        vmOverrides = {
          baseModules = [ ];
          defaultVmDir = "$HOME/.local/share/browser-vm";
          defaultMemory = 4096;
          defaultCores = 4;
          defaultDiskSize = 12;
          defaultEphemeral = false;
          defaultClipboard = false;
        };
      };
      guest =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
          modules = [ ./baguette.nix ];
        };
    in
    nixpkgs.lib.recursiveUpdate qemu (
      flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          configuration = guest system;
        in
        {
          packages = {
            baguette-zimage = configuration.config.system.build.btrfsImageCompressed;
            system = configuration.config.system.build.toplevel;
          };
          apps.sbom-baguette = aldur-dotfiles.lib.mkSbomApp {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit configuration;
          };
          checks.baguette-boot = import ./tests/baguette-boot.nix {
            inherit configuration;
            crostini = nixos-crostini;
          };
          checks.qemu-boot = import ./tests/qemu-boot.nix {
            pkgs = nixpkgs.legacyPackages.${system};
            specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
          };
        }
      )
      // {
        nixosConfigurations.browser = guest "aarch64-linux";
      }
    );
}
