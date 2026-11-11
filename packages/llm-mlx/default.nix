{
  pkgs ? (import <nixpkgs> { }),
}:
pkgs.callPackage ./llm-mlx.nix {
  inherit (pkgs.python3.pkgs)
    buildPythonPackage
    setuptools
    setuptools-scm
    llm
    mlx-lm
    ;
}
