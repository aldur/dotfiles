{
  description = "An NixOS ChromeOS guest from aldur's dotfiles.";

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

    preservation = {
      url = "github:nix-community/preservation";
    };
  };
  outputs =
    {
      self,
      nixos-generators,
      aldur-dotfiles,
      nixos-crostini,
      preservation,
      ...
    }:
    let
      modules = [
        aldur-dotfiles.nixosModules.default
        ./crostini.nix
      ];

      inherit (aldur-dotfiles.inputs) nixpkgs;
      specialArgs = {
        inputs = aldur-dotfiles.specialArgs.inputs // {
          inherit nixos-crostini;
          inherit preservation;
        };
      };

      crostiniModule = nixos-crostini.nixosModules.crostini;
      baguetteModule = nixos-crostini.nixosModules.baguette;
    in
    aldur-dotfiles.inputs.flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (system: {
        packages = rec {
          crostini-lxc = nixos-generators.nixosGenerate {
            inherit system specialArgs;
            modules = modules ++ [ crostiniModule ];
            format = "lxc";
          };
          default = crostini-lxc;

          crostini-lxc-metadata = nixos-generators.nixosGenerate {
            inherit system specialArgs modules;
            format = "lxc-metadata";
          };

          baguette-tarball = self.nixosConfigurations.baguette-nixos.config.system.build.tarball;
          baguette-image = self.nixosConfigurations.baguette-nixos.config.system.build.btrfsImage;
        };
      })
    // (
      let
        generator =
          system: moreModules:
          nixpkgs.lib.nixosSystem {
            inherit specialArgs system;
            modules = modules ++ moreModules;
          };

        lxc-nixos = generator "aarch64-linux" crostiniModule;
      in
      {
        nixosConfigurations = {
          # Having this allows rebuilding the image _within_ the container.
          inherit lxc-nixos;
          lxc-nixos-arm = lxc-nixos;
          lxc-nixos-x86 = generator "x86_64-linux" [ crostiniModule ];

          baguette-nixos = generator "aarch64-linux" [
            baguetteModule
            (_: {
              virtualisation.buildMemorySize = 1024 * 8;
            })
          ];
        };
      }
    );
}
