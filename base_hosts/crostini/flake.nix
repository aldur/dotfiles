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
      (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lxc = generator system [ crostiniModule ];
          baguette = generator system baguetteModules;
        in
        {
          packages = rec {
            # The crostini module imports `lxc-container.nix`. That module sets
            # `system.build.image` to the LXC tarball.
            # See: https://nixos.org/manual/nixos/stable/#sec-image-nixos-rebuild-build-image
            crostini-lxc = lxc.config.system.build.image;
            default = crostini-lxc;

            baguette-tarball = baguette.config.system.build.tarball;
            baguette-image = baguette.config.system.build.btrfsImage;
            baguette-zimage = baguette.config.system.build.btrfsImageCompressed;
            baguette-benchmark = nixos-crostini.lib.mkBaguetteBenchmark {
              configuration = baguette;
              extraSystemUnits = [
                "home-manager-${baguette.config.mainUser}.service"
              ];
            };
          };

          # The SBOM of the system in baguette-zimage. CI attests it to the
          # image.
          apps.sbom-baguette = aldur-dotfiles.lib.mkSbomApp {
            inherit pkgs;
            configuration = baguette;
          };

          # Simulates guest boot with the representative Termina kernel.
          # Real ChromeOS registration is checked separately on the device.
          checks.baguette-boot = pkgs.callPackage ./tests/baguette-boot.nix {
            configuration = baguette;
            crostini = nixos-crostini;
          };

          checks.baguette-verifier = nixos-crostini.checks.${system}.boot-verifier;

          checks.rebuild-resources = pkgs.callPackage ./tests/rebuild-resources.nix {
            inherit baguette lxc;
          };

          checks.ssh-configurations = pkgs.callPackage ./tests/ssh-configurations.nix {
            configurations = [
              lxc
              baguette
            ];
          };
        }
      )
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
