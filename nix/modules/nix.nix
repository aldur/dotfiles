{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  name = "determinate-nix";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = lib.mkEnableOption "Enable Determinate Nix (without FlakeHub)";
  };

  config = lib.mkMerge [
    {
      nix = {
        settings = {
          experimental-features = "nix-command flakes";
        };

        package = pkgs.nixVersions.latest;

        optimise = {
          automatic = true;
        };

        # Pin nixpkgs to the flake input, so that the packages installed
        # come from the flake inputs.nixpkgs.url.
        registry.nixpkgs.flake = inputs.nixpkgs;
      };
    }
    (lib.mkIf cfg.enable {
      nix.package = lib.mkForce inputs.detnix.packages."${pkgs.stdenv.system}".default;
    })
  ];
}
