{
  pkgs ? (import <nixpkgs> { }),
}:
let
  inherit (pkgs.python313Packages) mlx-lm;
  llm-mlx = pkgs.callPackage ./llm-mlx.nix {
    inherit (pkgs.python313Packages)
      buildPythonPackage
      setuptools
      setuptools-scm
      llm
      ;
    inherit mlx-lm;
  };
in
llm-mlx
