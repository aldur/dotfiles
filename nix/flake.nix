{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
      inputs.home-manager.follows = "home-manager";
      inputs.systems.follows = "systems";
    };

    nixCats.url = "github:BirdeeHub/nixCats-nvim";
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "";
      inputs.flake-compat.follows = "";
      inputs.treefmt-nix.follows = "";
      inputs.hercules-ci-effects.follows = "";
    };

    clipshare = {
      url = "github:aldur/clipshare";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { flake-utils, nixpkgs, home-manager, nix-index-database, ... }@inputs:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nixCatsLazyVim =
          (pkgs.callPackage ./packages/lazyvim/lazyvim.nix { inherit inputs; });
        defaultPackage = nixCatsLazyVim.defaultPackage;
      in { packages = inputs.nixCats.utils.mkAllWithDefault defaultPackage; }))
    // {

      templates = {
        vm-nogui = {
          path = ./base_hosts/qemu;
          description = "A QEMU VM";
        };
      };

    };
}
