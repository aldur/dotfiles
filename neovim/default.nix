let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./neovim.nix { }
