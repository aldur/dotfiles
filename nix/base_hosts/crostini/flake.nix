{
  description = "An lxc NixOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../../..?dir=nix";
      url = "github:aldur/dotfiles?dir=nix";
    };

    nixos-crostini = {
      url = "github:aldur/nixos-crostini";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
      inputs.nixos-generators.follows = "nixos-generators";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };
  outputs = { self, nixos-generators, aldur-dotfiles, nixos-crostini, ... }:
    let
      modules = [ aldur-dotfiles.nixosModules.default ./crostini.nix ];

      nixpkgs = aldur-dotfiles.inputs.nixpkgs;
      specialArgs = {
        inputs = aldur-dotfiles.specialArgs.inputs // {
          inherit nixos-crostini;
        };
      };

      crostiniModule = nixos-crostini.nixosModules.crostini;
      baguetteModule = nixos-crostini.nixosModules.baguette;
    in aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages = rec {
        crostini-lxc = nixos-generators.nixosGenerate {
          inherit system specialArgs;
          modules = modules ++ [ crostiniModule ];
          format = "lxc";
        };

        crostini-lxc-metadata = nixos-generators.nixosGenerate {
          inherit system specialArgs modules;
          format = "lxc-metadata";
        };

        baguette-image = let
          config = self.nixosConfigurations.baguette-nixos.config;
          img = config.system.build.btrfsImage;
        in nixpkgs.lib.overrideDerivation img
        (old: { requiredSystemFeatures = [ ]; }); # Disable `kvm` requirement.

        default = crostini-lxc;
      };
    }) // (let
      generator = system: module:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = modules ++ [ module ];
        };

      lxc-nixos = generator "aarch64-linux" crostiniModule;
    in {
      # Having this allows rebuilding the image _within_ the container.
      nixosConfigurations.lxc-nixos = lxc-nixos;
      nixosConfigurations.lxc-nixos-arm = lxc-nixos;
      nixosConfigurations.lxc-nixos-x86 =
        generator "x86_64-linux" crostiniModule;

      nixosConfigurations.baguette-nixos =
        generator "aarch64-linux" baguetteModule;
    });
}
