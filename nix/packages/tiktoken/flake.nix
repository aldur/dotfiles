{
  description = "A token counter implemented through `tiktoken`.";

  inputs = { aldur-dotfiles = { url = "git+file://../../../..?dir=nix"; }; };

  outputs = { aldur-dotfiles, ... }:
    let count-tokens = pkgs: pkgs.callPackage ./tiktoken.nix { };
    in aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: rec {
      legacyPackages = import aldur-dotfiles.inputs.nixpkgs { inherit system; };
      devShells.default = legacyPackages.mkShell {
        inherit (count-tokens legacyPackages) propagatedBuildInputs;
      };
      packages.default = count-tokens legacyPackages;
    }) // {
      overlays.default = final: prev: { count-tokens = (count-tokens prev); };
    };
}
