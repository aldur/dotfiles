# Shared configuration between NixOS and nix-darwin
{ inputs, ... }:

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
    ./modules/users.nix

    (
      { config, ... }:
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "home-manager-backup";

        # Optionally, use home-manager.extraSpecialArgs to pass
        # arguments to home.nix
        home-manager.extraSpecialArgs = {
          stateVersion = config.system.stateVersion;
          inherit inputs;
        };
      }
    )

    (
      { config, pkgs, ... }:
      {
        nixpkgs.config.allowUnfreePredicate = (
          pkg: builtins.elem (pkgs.lib.getName pkg) config.nixpkgs.allowUnfreeByName
        );
      }
    )
  ];
}
