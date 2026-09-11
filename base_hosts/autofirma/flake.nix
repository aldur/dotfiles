{
  description = "A QEMU NixOS guest that runs AutoFirma, from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };

    autofirma-nix = {
      url = "github:nix-community/autofirma-nix";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
      inputs.home-manager.follows = "aldur-dotfiles/home-manager";
    };

    nixos-crostini = {
      url = "github:aldur/nixos-crostini";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };

  outputs =
    { aldur-dotfiles, ... }@inputs:
    let
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;
      inherit (nixpkgs) lib;

      specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      guest = aldur-dotfiles.lib.mkQemuGuest {
        inherit inputs;
        name = "autofirma-vm";
        hostName = "autofirma-vm";
        qemuModule = ./autofirma.nix;

        vmOverrides = {
          defaultVmDir = "$HOME/.local/share/autofirma-vm";
          defaultMemory = 4096;
          defaultCores = 4;
          defaultDiskSize = 16;
          # Nothing survives a session: no profile, no cookies, no CA. The
          # certificate comes in with `--file` each time.
          defaultEphemeral = true;
          defaultClipboard = true;
        };
      };

      # The same guest as a ChromeOS Baguette image. See baguette.nix.
      mkBaguette =
        system:
        lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./baguette.nix ];
        };
      baguette = {
        nixosConfigurations = {
          # The hostname names the configuration: `nixos-rebuild` inside the
          # VM selects it that way.
          autofirma-baguette = mkBaguette "aarch64-linux";
          autofirma-baguette-x86_64 = mkBaguette "x86_64-linux";
        };
      }
      // flake-utils.lib.eachSystem linuxSystems (system: {
        packages.baguette-zimage = (mkBaguette system).config.system.build.btrfsImageCompressed;
        # The SBOM of the same system. CI attests it to the image.
        apps.sbom-baguette = aldur-dotfiles.lib.mkSbomApp {
          pkgs = nixpkgs.legacyPackages.${system};
          configuration = mkBaguette system;
        };
      });

      checks = flake-utils.lib.eachSystem linuxSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          testCert = import ./tests/test-cert.nix { inherit pkgs; };
          baguetteConfiguration = mkBaguette system;
        in
        {
          checks = rec {
            # Boots the QEMU guest, imports a test certificate into Firefox,
            # and signs a document through the afirma:// WebSocket flow.
            sign-via-websocket = pkgs.callPackage ./tests/sign-via-websocket.nix {
              guestModule = ./autofirma.nix;
              baseModule = aldur-dotfiles.nixosModules.default;
              inherit specialArgs;
              inherit (inputs) autofirma-nix;
              production = guest.nixosConfigurations."autofirma-vm-${lib.removeSuffix "-linux" system}";
            };

            qemu-configuration = import ./tests/qemu-configuration.nix {
              inherit pkgs lib;
              production = guest.nixosConfigurations."autofirma-vm-${lib.removeSuffix "-linux" system}".config;
              tested = sign-via-websocket.nodes.machine;
            };

            baguette-boot = import ./tests/baguette.nix {
              inherit pkgs lib testCert;
              configuration = baguetteConfiguration;
              crostini = inputs.nixos-crostini;
              inherit (aldur-dotfiles.lib) mkBaguetteSmokeTest;
            };

            baguette-no-linger = aldur-dotfiles.lib.mkBaguetteSmokeTest {
              configuration = baguetteConfiguration.extendModules {
                modules = [
                  {
                    users.users.${baguetteConfiguration.config.mainUser}.linger = lib.mkForce false;
                  }
                ];
              };
              crostini = inputs.nixos-crostini;
              name = "autofirma-baguette-no-linger";
              expectUserManager = false;
            };
          };
        }
      );

    in
    lib.foldl lib.recursiveUpdate { } [
      guest
      baguette
      checks
    ];
}
