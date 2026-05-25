let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./md2html.nix { }
