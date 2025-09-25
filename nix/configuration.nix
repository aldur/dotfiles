{
  lib,
  inputs,
  ...
}:

{
  imports = [
    ./modules/nixos/fish.nix
    ./modules/nixos/security.nix
    ./modules/nixos/ssh.nix
    ./modules/nixos/users.nix

    ./modules/aws.nix
    ./modules/cli.nix
    ./modules/dict.nix
    ./modules/direnv.nix
    ./modules/development.nix
    ./modules/environment.nix
    ./modules/fish.nix
    ./modules/locales.nix
    ./modules/neovim.nix
    ./modules/nix.nix
    ./modules/nix_search.nix
    ./modules/users.nix

    ./modules/lazyvim.nix

    inputs.agenix.nixosModules.default
    ./modules/agenix.nix

    inputs.home-manager.nixosModules.home-manager
    (
      { config, ... }:
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        # Optionally, use home-manager.extraSpecialArgs to pass
        # arguments to home.nix
        home-manager.extraSpecialArgs = {
          stateVersion = config.system.stateVersion;
          inherit inputs;
        };

        home-manager.users.aldur = ./home.nix;
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

  # By default we use DHCP
  networking.useDHCP = lib.mkDefault true;

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "24.11"; # Did you read the comment?

  # Doesn't play nicely with flakes.
  programs.command-not-found.enable = false;
}
