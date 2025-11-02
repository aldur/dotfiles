# macOS-specific configuration
{ inputs, ... }:
let
  user = "aldur";
in
{
  imports = [
    ../../configuration.nix

    inputs.home-manager.darwinModules.home-manager
    inputs.nix-index-database.darwinModules.nix-index

    ./defaults.nix
    ./homebrew.nix
    ./keyboard.nix
    ./nixpkgs.nix
    ./linux-builder.nix
    ./packages.nix
    ./security.nix
  ];

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6; # Did you read the comment?

  users.users.${user} = {
    home = "/Users/${user}";
    uid = 501;
  };

  # See https://github.com/nix-darwin/nix-darwin/issues/1237
  users.knownUsers = [ user ];

  # Set `defaults` for this user
  system.primaryUser = user;

  home-manager.users.${user} = ./home.nix;
  # Use home-manager.extraSpecialArgs to pass arguments to home.nix
  home-manager.extraSpecialArgs = {
    stateVersion = "25.05"; # Can't share it with nix-darwin as we do for NixOS
    inherit inputs;
  };
}
