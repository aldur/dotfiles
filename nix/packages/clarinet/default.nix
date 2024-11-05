let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./clarinet.nix { }
