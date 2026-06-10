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

      # `apple-container.nix` → lightweight `container run` image;
      # `apple-machine.nix` → full-system `container machine` image. Both share
      # `common.nix` and the base modules.
      mkSystem =
        system: hostModule:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            aldur-dotfiles.nixosModules.default
            hostModule
          ];
        };

      containerCfg = system: mkSystem system ./apple-container.nix;
      machineCfg = system: mkSystem system ./apple-machine.nix;
    in
    # The image is always a Linux artifact. On a Darwin host (the usual case —
    # Apple silicon) map to the matching linux system so `#container-image`
    # works directly and offloads to the user's Linux builder. Building the
    # aarch64 image natively needs an aarch64 builder.
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        targetSystem =
          {
            aarch64-darwin = "aarch64-linux";
            x86_64-darwin = "x86_64-linux";
          }
          .${system} or system;
      in
      {
        packages = rec {
          container-image = (containerCfg targetSystem).config.system.build.containerImage;
          machine-image = (machineCfg targetSystem).config.system.build.containerImage;
          default = container-image;
        };
      }
    )
    // {
      nixosConfigurations = {
        apple-container = containerCfg "aarch64-linux";
        apple-container-aarch64 = containerCfg "aarch64-linux";
        apple-container-x86_64 = containerCfg "x86_64-linux";

        apple-machine = machineCfg "aarch64-linux";
        apple-machine-aarch64 = machineCfg "aarch64-linux";
        apple-machine-x86_64 = machineCfg "x86_64-linux";
      };
    };
}
