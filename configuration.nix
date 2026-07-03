# Shared configuration between NixOS and nix-darwin
{ ... }:

{
  imports = [
    ./modules/aws.nix
    ./modules/cli.nix
    ./modules/development.nix
    ./modules/dict.nix
    ./modules/environment.nix
    ./modules/fish.nix
    ./modules/lazyvim.nix
    ./modules/nix.nix
    ./modules/nixpkgs.nix
    ./modules/users.nix

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
}
