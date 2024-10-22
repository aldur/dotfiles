{
  description = "A simple Telegram notifier.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.systems.url = "github:nix-systems/default";
  inputs.flake-utils = {
    url = "github:numtide/flake-utils";
    inputs.systems.follows = "systems";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    let
      telegram = pkgs: pkgs.stdenv.mkDerivation {
        name = "telegram";
        nativeBuildInputs = [
          pkgs.curl
        ];
        src = ./telegram.sh;
        dontUnpack = true;
        buildPhase = ''
          install -Dm755 ${./telegram.sh} $out/bin/telegram
        '';
      };
    in
    flake-utils.lib.eachDefaultSystem
      (
        system:
        rec {
          legacyPackages = import nixpkgs {
            inherit system;
          };
          packages.default = telegram legacyPackages;
        }
      ) // {
      overlays.default = final: prev: {
        count-tokens = (telegram prev);
      };
    };
}
