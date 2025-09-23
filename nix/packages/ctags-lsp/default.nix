let
  pkgs = import <nixpkgs> {};
in
  pkgs.callPackage ./ctags-lsp.nix {}
