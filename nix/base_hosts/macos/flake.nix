{
  description = "nix-darwin configuration from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../../..?dir=nix";
      url = "github:aldur/dotfiles?dir=nix";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };

    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "aldur-dotfiles/nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };
  outputs =
    { nix-darwin, aldur-dotfiles, ... }@inputs:
    let
      modules = [
        "${aldur-dotfiles}/modules/darwin/configuration.nix"
        ./macos.nix
      ];

      specialArgs = {
        # Order is important, we want "self" to be "aldur-dotfiles".
        inputs = inputs // aldur-dotfiles.specialArgs.inputs;
      };
    in
    {
      darwinConfigurations."macOS" = nix-darwin.lib.darwinSystem { inherit specialArgs modules; };
    };
}
