{
  description = "A QEMU NixOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      url = "git+file://../../../..?dir=nix";
      # url = "github:aldur/dotfiles?dir=nix";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };
  };
  outputs = { nixos-generators, aldur-dotfiles, ... }:
    let
      modules = [ "${aldur-dotfiles}/configuration.nix" ];

      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system
      specialArgs =
        # This ugly thing is ensuring all the right inputs go to `aldur-dotfiles`,
        # including itself.
        let inputs = aldur-dotfiles.inputs // { self = aldur-dotfiles; };
        in { inherit inputs; };
    in aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import aldur-dotfiles.inputs.nixpkgs { inherit system; };
      in {
        packages = {
          vm-nogui = nixos-generators.nixosGenerate {
            system = "aarch64-linux";
            specialArgs = specialArgs // { hostPkgs = pkgs; };
            modules = modules ++ [ ({ ... }: { imports = [ ./qemu.nix ]; }) ];
            format = "vm-nogui";
          };
        };
      });
}
