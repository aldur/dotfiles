let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./tiktoken.nix { }
