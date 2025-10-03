# macOS-specific configuration
{ inputs, ... }:
let user = "aldur";
in {
  imports = [
    ../../configuration.nix

    inputs.home-manager.darwinModules.home-manager
    inputs.nix-index-database.darwinModules.nix-index
  ];

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6; # Did you read the comment?

  users.users.${user} = { home = "/Users/${user}"; };
  home-manager.users.${user} = ./home.nix;
  # Use home-manager.extraSpecialArgs to pass arguments to home.nix
  home-manager.extraSpecialArgs = {
    stateVersion = "25.05"; # Can't share it with nix-darwin as we do for NixOS
    inherit inputs;
  };
}
