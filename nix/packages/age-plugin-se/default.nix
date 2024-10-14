let
  pkgs = import <nixpkgs> {};
in
  pkgs.callPackage ./age-plugin-se.nix {}
