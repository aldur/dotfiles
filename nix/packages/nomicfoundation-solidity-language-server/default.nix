let
  pkgs = import <nixpkgs> { };
in
pkgs.callPackage ./nomicfoundation-solidity-language-server.nix { }
