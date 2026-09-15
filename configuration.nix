# Shared configuration between NixOS and nix-darwin
{
  pkgs,
  lib,
  ...
}:
let
  packages = import ./modules/shared/environment.nix {
    inherit pkgs lib;
  };
in
{
  imports = [
    ./modules/aws.nix
    ./modules/dict.nix
    ./modules/fish.nix
    ./modules/nix.nix
    ./modules/nixpkgs.nix

    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "home-manager-backup";
      };
    }

    (
      { inputs, ... }:
      let
        inherit (inputs) self;
      in
      {
        # https://discourse.nixos.org/t/flakes-accessing-selfs-revision/11237/8
        # Show with `nixos-version --configuration-revision`
        system.configurationRevision = toString (
          self.shortRev or self.dirtyShortRev or self.lastModified or "unknown"
        );
      }
    )
  ];

  environment.systemPackages = packages.cli ++ packages.terminfo;
}
