{
  description = "A QEMU NixOS guest that runs AutoFirma, from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };

    # AutoFirma, its Java truststore and the Firefox integration. Kept on
    # its own nixpkgs: the Maven dependency hashes pinned below were
    # probed against it and would drift with another maven/jdk.
    autofirma-nix = {
      url = "github:nix-community/autofirma-nix";
      inputs.home-manager.follows = "aldur-dotfiles/home-manager";
    };
  };

  outputs =
    {
      self,
      aldur-dotfiles,
      autofirma-nix,
      ...
    }@inputs:
    let
      specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;

      guestModule = ./guest.nix;
      qemuModule = ./autofirma.nix;

      # A browser plus a Java desktop app: far below the qemu-vm defaults.
      vmDefaults = {
        defaultVmDir = "$HOME/.local/share/autofirma-vm";
        defaultMemory = 4096;
        defaultCores = 4;
        defaultDiskSize = 16;
      };
    in
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          packages = rec {
            autofirma-vm = aldur-dotfiles.legacyPackages.${system}.qemu-vm.override (
              vmDefaults
              // {
                inherit qemuModule;
                # The guest module reads `inputs.autofirma-nix`; the dotfiles
                # package only knows the dotfiles inputs.
                inherit (specialArgs) inputs;
              }
            );
            default = autofirma-vm;
          };

          checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            # Boots the guest, imports a test certificate into Firefox and
            # signs a document through the afirma:// WebSocket flow.
            sign-via-websocket = pkgs.callPackage ./tests/sign-via-websocket.nix {
              inherit specialArgs guestModule;
              baseModule = aldur-dotfiles.nixosModules.default;
              autofirma-nix = inputs.autofirma-nix;
            };
          };
        }
      )
    // (
      let
        cfg =
          targetSystem:
          nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            modules = aldur-dotfiles.legacyPackages.${targetSystem}.qemu-vm.modules ++ [ qemuModule ];
            system = targetSystem;
          };

        autofirma-nixos-aarch64 = cfg "aarch64-linux";
        autofirma-nixos-x86_64 = cfg "x86_64-linux";
      in
      {
        nixosConfigurations = {
          autofirma-nixos = autofirma-nixos-aarch64;
          inherit autofirma-nixos-aarch64 autofirma-nixos-x86_64;
        };
      }
    );
}
