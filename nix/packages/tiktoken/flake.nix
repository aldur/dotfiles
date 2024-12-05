{
  description = "A token counter implemented through `tiktoken`.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.systems.url = "github:nix-systems/default";
  inputs.flake-utils = {
    url = "github:numtide/flake-utils";
    inputs.systems.follows = "systems";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    let
      count-tokens = pkgs: pkgs.callPackage ./tiktoken.nix { };
    in
    flake-utils.lib.eachDefaultSystem (system: rec {
      legacyPackages = import nixpkgs {
        inherit system;
      };
      devShells.default = legacyPackages.mkShell {
        inherit (count-tokens legacyPackages) propagatedBuildInputs;
      };
      packages.default = count-tokens legacyPackages;
    })
    // {
      overlays.default = final: prev: {
        count-tokens = (count-tokens prev);
      };
    };
}
