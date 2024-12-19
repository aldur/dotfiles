let
  pkgs = import <nixpkgs> {};
in
  pkgs.callPackage ./llmcat.nix {}
