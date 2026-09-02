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
  };

  outputs =
    { aldur-dotfiles, ... }@inputs:
    let
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;

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
        };
      };

      # Boots the guest, imports a test certificate into Firefox, and signs
      # a document through the afirma:// WebSocket flow.
      checks =
        flake-utils.lib.eachSystem
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
          (system: {
            checks.sign-via-websocket =
              nixpkgs.legacyPackages.${system}.callPackage ./tests/sign-via-websocket.nix
                {
                  guestModule = ./guest.nix;
                  baseModule = aldur-dotfiles.nixosModules.default;
                  specialArgs = aldur-dotfiles.lib.mkSpecialArgs inputs;
                  inherit (inputs) autofirma-nix;
                };
          });
    in
    guest // checks;
}
