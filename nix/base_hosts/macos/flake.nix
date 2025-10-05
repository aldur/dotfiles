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

      specialArgs = aldur-dotfiles.specialArgs;
    in {
      darwinConfigurations."macOS" =
        nix-darwin.lib.darwinSystem { inherit specialArgs modules; };
    };
}
