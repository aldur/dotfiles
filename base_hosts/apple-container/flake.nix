{
  description = "A NixOS OCI image for Apple `container` (run + machine), from aldur's dotfiles.";

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

      # One image serves both: `container run` uses the OCI entrypoint, while
      # `container machine` execs /sbin/init. Same closure, two entry doors.
      cfg =
        system:
        nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            aldur-dotfiles.nixosModules.default
            ./configuration.nix
          ];
        };

      minimal =
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            (nixpkgs + "/nixos/modules/profiles/minimal.nix")
            ./apple-container.nix
            {
              system.stateVersion = nixpkgs.lib.trivial.release;
              virtualisation.appleContainer = {
                username = "nixos";
                imageName = "nixos";
              };
              users.users.nixos.extraGroups = [ "wheel" ];
              nix.settings.experimental-features = [
                "nix-command"
                "flakes"
              ];
            }
          ];
        };
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
          container-image = (cfg targetSystem).config.system.build.containerImage;
          minimal-image = (minimal targetSystem).config.system.build.containerImage;
          default = container-image;
        };
      }
    )
    // {
      # The generic part — anyone can import this into their own
      # nixosConfiguration (no dependency on aldur's dotfiles) and build
      # `config.system.build.containerImage`. See the
      # `virtualisation.appleContainer` options in apple-container.nix.
      nixosModules = rec {
        apple-container = ./apple-container.nix;
        default = apple-container;
      };

      nixosConfigurations = {
        apple-container = cfg "aarch64-linux";
        apple-container-aarch64 = cfg "aarch64-linux";
        apple-container-x86_64 = cfg "x86_64-linux";
      };
    };
}
