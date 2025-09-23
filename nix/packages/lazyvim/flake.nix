{
  description = "LazyVim in `nix`";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixCats.url = "github:BirdeeHub/nixCats-nvim";

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "";
      inputs.flake-compat.follows = "";
      inputs.treefmt-nix.follows = "";
      inputs.hercules-ci-effects.follows = "";
    };
  };

  outputs =
    {
      nixpkgs,
      nixCats,
      ...
    }@inputs:
    let
      inherit (nixCats) utils;
      forEachSystem = utils.eachSystem nixpkgs.lib.platforms.all;
    in
    forEachSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        nixCatsLazyVim = (pkgs.callPackage ./lazyvim.nix { inherit inputs; });
        defaultPackage = nixCatsLazyVim.defaultPackage;
        overlays = nixCatsLazyVim.overlays;
      in
      {
        inherit overlays;
        packages = utils.mkAllWithDefault defaultPackage;
      }
    );
}
