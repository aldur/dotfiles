{
  description = "An NixOS ChromeOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };

    nixos-crostini = {
      url = "github:aldur/nixos-crostini";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };
  outputs =
    {
      self,
      aldur-dotfiles,
      nixos-crostini,
      ...
    }@inputs:
    let
      modules = [
        aldur-dotfiles.nixosModules.default
        ./crostini.nix
      ];

      inherit (aldur-dotfiles.inputs) nixpkgs;
      specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;

      crostiniModule = nixos-crostini.nixosModules.crostini;
      baguetteModules = [
        aldur-dotfiles.nixosModules.baguette-guest
        ./baguette.nix
      ];

      generator =
        system: moreModules:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = modules ++ moreModules;
        };

      lxc-nixos = generator "aarch64-linux" [ crostiniModule ];
    in
    aldur-dotfiles.inputs.flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (system: {
        packages = rec {
          # The crostini module imports `lxc-container.nix`. That module sets
          # `system.build.image` to the LXC tarball.
          # See: https://nixos.org/manual/nixos/stable/#sec-image-nixos-rebuild-build-image
          crostini-lxc = (generator system [ crostiniModule ]).config.system.build.image;
          default = crostini-lxc;

          baguette-tarball = self.nixosConfigurations.baguette-nixos.config.system.build.tarball;
          baguette-image = self.nixosConfigurations.baguette-nixos.config.system.build.btrfsImage;
          baguette-zimage = self.nixosConfigurations.baguette-nixos.config.system.build.btrfsImageCompressed;
        };

        # The SBOM of the system in baguette-zimage. CI attests it to the
        # image.
        apps.sbom-baguette = aldur-dotfiles.lib.mkSbomApp {
          pkgs = nixpkgs.legacyPackages.${system};
          configuration = self.nixosConfigurations.baguette-nixos;
        };

        # Simulates guest boot with the representative Termina kernel.
        # Real ChromeOS registration is checked separately on the device.
        checks.baguette-boot = nixpkgs.legacyPackages.${system}.callPackage ./tests/baguette-boot.nix {
          configuration = generator system baguetteModules;
          inherit (aldur-dotfiles.lib) mkBaguetteSmokeTest;
          crostini = nixos-crostini;
        };

        # Compatibility alias: all smoke boots now use the Termina kernel.
        checks.baguette-boot-termina = self.checks.${system}.baguette-boot;

        checks.baguette-verifier = import ./tests/verify-boot.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          crostini = nixos-crostini;
        };

        checks.ssh-configurations =
          nixpkgs.legacyPackages.${system}.callPackage ./tests/ssh-configurations.nix
            {
              configurations = [
                (generator system [ crostiniModule ])
                (generator system baguetteModules)
              ];
            };
      })
    // {
      nixosConfigurations = {
        # Having this allows rebuilding the image _within_ the container.
        inherit lxc-nixos;
        lxc-nixos-arm = lxc-nixos;
        lxc-nixos-x86 = generator "x86_64-linux" [ crostiniModule ];

        baguette-nixos = generator "aarch64-linux" baguetteModules;
      };
    };
}
