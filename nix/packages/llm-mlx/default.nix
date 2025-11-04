{
  pkgs ? (import <nixpkgs> { }),
}:
pkgs.callPackage ./llm-mlx.nix {
  inherit (pkgs.python313Packages)
    buildPythonPackage
    setuptools
    setuptools-scm
    llm
    mlx-lm
    ;
}
