{
  description = "nix-darwin configuration from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../../..?dir=nix";
      url = "github:aldur/dotfiles?dir=nix";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
  };
  outputs = { nix-darwin, aldur-dotfiles, ... }:
    let
      modules =
        [ "${aldur-dotfiles}/modules/darwin/configuration.nix" ./macos.nix ];

      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system
      specialArgs =
        # This ugly thing is ensuring all the right inputs go to `aldur-dotfiles`,
        # including itself.
        let inputs = aldur-dotfiles.inputs // { self = aldur-dotfiles; };
        in { inherit inputs; };
    in {
      darwinConfigurations."macOS" =
        nix-darwin.lib.darwinSystem { inherit specialArgs modules; };
    };
}
