{ pkgs ? (import <nixpkgs> { }) }:
let
  # https://github.com/NixOS/nixpkgs/pull/410209/
  # files#diff-164ac33bd81657ce137c6a7a132cee952f428fd2f41ddadd859a2e075673e2c3
  # Might not be required anymore once this merges.
  mlx = pkgs.callPackage ./mlx-pypi.nix {
    inherit (pkgs.python312Packages)
      buildPythonPackage
      fetchPypi
      ;
  };
  mlx-lm = pkgs.callPackage ./mlx-lm.nix {
    inherit (pkgs.python312Packages)
      buildPythonPackage
      numpy
      transformers
      protobuf
      pyyaml
      jinja2
      ;
    inherit mlx;
  };
  llm-mlx = pkgs.callPackage ./llm-mlx.nix {
    inherit (pkgs.python312Packages)
      buildPythonPackage
      setuptools
      setuptools-scm
      llm
      ;
    inherit mlx-lm;
  };
in
llm-mlx
