let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./schemat.nix { }
