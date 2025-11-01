{ lib, pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Disable to allow Determinate Nix
  nix.enable = false;
  nix.optimise.automatic = lib.mkForce false;

  # Set to true to enable homebrew integration.
  programs.homebrew.enable = false;

  # Then, add brews, casks, and masApps here
  homebrew = {
    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.masApps
    masApps = { };

    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.brews
    brews = [ ];

    casks = [ ];
  };

  home-manager.users.aldur =
    { ... }:
    {
      # Set to true for https://github.com/simonw/llm and plugins support
      programs.llm.enable = false;

      home.packages = with pkgs; [ git-crypt ];

      programs.aldur.lazyvim.enable = true;
      programs.aldur.lazyvim.packageNames = [ "lazyvim" ];
    };
}
