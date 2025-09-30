# NixOS-specific configuration
{ inputs, lib, config, ... }: {
  imports = [
    ../../configuration.nix

    ./fish.nix
    ./security.nix
    ./ssh.nix
    ./users.nix
    ./locales.nix
    ./default_editor.nix
    ./agenix.nix

    # NixOS-specific modules go here.
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
  ];

  # We use DHCP by default.
  networking.useDHCP = lib.mkDefault true;

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "24.11"; # Did you read the comment?

  # Doesn't play nicely with flakes.
  programs.command-not-found.enable = false;

  home-manager.users.aldur = ./home.nix;
  # Use home-manager.extraSpecialArgs to pass arguments to home.nix
  home-manager.extraSpecialArgs = {
    stateVersion = config.system.stateVersion;
    inherit inputs;
  };
}
