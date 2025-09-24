{
  description = "A simple Telegram notifier.";

  inputs = { aldur-dotfiles = { url = "git+file://../../../..?dir=nix"; }; };

  outputs = { aldur-dotfiles, ... }:
    let
      telegram = pkgs:
        pkgs.stdenv.mkDerivation rec {
          name = "telegram";
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildIputs = [ pkgs.curl ];
          src = ./telegram.sh;
          dontUnpack = true;
          buildPhase = ''
            install -Dm755 ${./telegram.sh} $out/bin/telegram
          '';
          postFixup = ''
            wrapProgram $out/bin/telegram \
              --set PATH ${pkgs.lib.makeBinPath buildIputs}
          '';
        };
    in aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system: rec {
      legacyPackages = import aldur-dotfiles.inputs.nixpkgs { inherit system; };
      packages.default = telegram legacyPackages;
    }) // {
      overlays.default = final: prev: { count-tokens = (telegram prev); };
    };
}
