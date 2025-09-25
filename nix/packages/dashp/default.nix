let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./dashp.nix { }
