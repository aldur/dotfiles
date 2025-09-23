{
  description = "aldur's nvim configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";

    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    neovim-nightly-overlay.inputs.nixpkgs.follows = "nixpkgs";
    neovim-nightly-overlay.inputs.git-hooks.follows = "";
    neovim-nightly-overlay.inputs.flake-compat.follows = "";
    neovim-nightly-overlay.inputs.treefmt-nix.follows = "";
    neovim-nightly-overlay.inputs.hercules-ci-effects.follows = "";
  };

  outputs =
    {
      nixpkgs,
      utils,
      neovim-nightly-overlay,
      ...
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        packages = rec {
          neovim-nightly = pkgs.callPackage ./neovim.nix {
            nvim-package = neovim-nightly-overlay.packages.${pkgs.system}.default;
          };
          neovim = pkgs.callPackage ./neovim.nix { };
          default = neovim;
        };
      }
    );
}
