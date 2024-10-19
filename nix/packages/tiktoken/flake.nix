{
  description = "A token counter implemented through `tiktoken`.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.systems.url = "github:nix-systems/default";
  inputs.flake-utils = {
    url = "github:numtide/flake-utils";
    inputs.systems.follows = "systems";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    let
      pkgsForSystem = system: nixpkgs.legacyPackages.${system};
      pythonEnv = pkgsForSystem.python312.withPackages (ps: with ps; [ tiktoken ]);

      count-tokens = pkgs: pkgs.stdenv.mkDerivation {
        name = "count-tokens-0.1";
        propagatedBuildInputs = [ pythonEnv ];
        dontUnpack = true;
        installPhase = "install -Dm755 ${./count_tokens.py} $out/bin/count-tokens";
      };
    in
    flake-utils.lib.eachDefaultSystem
      (
        system:
        rec {
          legacyPackages = pkgsForSystem system;
          devShells.default = legacyPackages.mkShell {
            buildInputs = [ pythonEnv ];
          };
          packages.default = count-tokens legacyPackages;
        }
      ) // {
      overlays.default = final: prev: {
        count-tokens = count-tokens prev;
      };
    };
}
