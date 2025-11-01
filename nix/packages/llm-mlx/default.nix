{ pkgs ? (import <nixpkgs> { }) }:
let
  mlx-lm = pkgs.python312Packages.mlx-lm;
  llm-mlx = pkgs.callPackage ./llm-mlx.nix {
    inherit (pkgs.python312Packages)
      buildPythonPackage setuptools setuptools-scm llm;
    inherit mlx-lm;
  };
in llm-mlx
