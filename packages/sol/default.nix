let
  pkgs = import <nixpkgs> {};
in
  pkgs.callPackage ./sol.nix {}
