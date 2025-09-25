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
  outputs =
    {
      nixos-generators,
      aldur-dotfiles,
      nixos-crostini,
      ...
    }:
    let
      modules = [
        "${aldur-dotfiles}/configuration.nix"
        ./lxc.nix
      ];

      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system
      specialArgs =
        # This ugly thing is ensuring all the right inputs go to `aldur-dotfiles`,
        # including itself.
        let
          inputs = aldur-dotfiles.inputs // {
            inherit nixos-crostini;
            self = aldur-dotfiles;
          };
        in
        {
          inherit inputs;
        };

      nixpkgs = aldur-dotfiles.inputs.nixpkgs;
    in
    aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: {
      packages = rec {
        lxc = nixos-generators.nixosGenerate {
          inherit system specialArgs modules;
          format = "lxc";
        };

        lxc-metadata = nixos-generators.nixosGenerate {
          inherit system specialArgs modules;
          format = "lxc-metadata";
        };

        default = lxc;
      };
    })
    // (
      let
        generator =
          system:
          nixpkgs.lib.nixosSystem {
            inherit specialArgs system modules;
          };

        lxc-nixos = generator "aarch64-linux";
      in
      {
        # Having this allows rebuilding the image _within_ the container.
        nixosConfigurations.lxc-nixos = lxc-nixos;
        nixosConfigurations.lxc-nixos-arm = lxc-nixos;
        nixosConfigurations.lxc-nixos-x86 = generator "x86_64-linux";
      }
    );
}
