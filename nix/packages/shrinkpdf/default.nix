{ pkgs ? import <nixpkgs> { } }:
pkgs.callPackage ./shrinkpdf.nix { }
