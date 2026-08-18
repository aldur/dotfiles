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
      };
    }

    # Pin nixpkgs to the flake input's rev, by reference.
    # The narHash lets nix resolve store-first, so no fetch on machines that
    # evaluated the flake; elsewhere it's a one-time tarball per rev.
    {
      nix.registry.nixpkgs.to =
        let
          # The branch this system is actually built from — the darwin
          # binary cache covers nixpkgs-darwin revs, not nixos ones.
          base = if pkgs.stdenv.hostPlatform.isDarwin then inputs.nixpkgs-darwin else inputs.nixpkgs;
        in
        {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          inherit (base) rev narHash;
        };
    }

    (lib.mkIf cfg.enable {
      nix.package = lib.mkForce (
        inputs.detnix.packages."${pkgs.stdenv.hostPlatform.system}".default.overrideAttrs {
          doCheck = false;
          doInstallCheck = false;
        }
      );
      # https://docs.determinate.systems/guides/telemetry
      environment.variables = {
        DETSYS_IDS_TELEMETRY = "disabled";
      };
    })
  ];
}
