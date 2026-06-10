{
  description = "A NixOS OCI image for Apple `container`, from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };
  };
  outputs =
    { aldur-dotfiles, ... }:
    let
      inherit (aldur-dotfiles) specialArgs;
      inherit (aldur-dotfiles.inputs) nixpkgs flake-utils;

      containerModule = ./apple-container.nix;

      cfg =
        system:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            aldur-dotfiles.nixosModules.default
            containerModule
          ];
        };
    in
    # Building the aarch64 image (the Apple-silicon target) needs an aarch64
    # builder; x86_64 is kept for parity and CI, mirroring the other hosts.
    flake-utils.lib.eachSystem
      [
        "aarch64-linux"
        "x86_64-linux"
      ]
      (system: {
        packages = rec {
          container-image = (cfg system).config.system.build.containerImage;
          default = container-image;
        };
      })
    // {
      nixosConfigurations = {
        apple-container = cfg "aarch64-linux";
        apple-container-aarch64 = cfg "aarch64-linux";
        apple-container-x86_64 = cfg "x86_64-linux";
      };
    };
}
