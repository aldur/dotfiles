{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Set to true to enable homebrew integration.
  programs.homebrew.enable = false;

  # To enable the smarter Linux builder:
  #
  # 1. Set
  # nix.linux-builder.enable = true;
  # 2. Rebuild
  # 3. Set
  # nix.linux-builder.enable = false;
  # 4. Set `services.linux-builder.enable` to true.
  services.linux-builder.enable = false;

  # Set to true if you want to use Determinate Nix
  programs.determinate-nix.enable = false;

  # Then, add brews, casks, and masApps here
  homebrew = {
    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.masApps
    masApps = { };

    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.brews
    brews = [ ];

    casks = [ ];
  };

  home-manager.users.aldur = _: {
    programs = {
      # Set to true for https://github.com/simonw/llm and plugins support
      llm.enable = false;

      aldur.lazyvim.enable = true;
      aldur.lazyvim.packageNames = [ "lazyvim" ];
    };

    home.packages = with pkgs; [
      git-crypt

      # In case you want to jail lazyvim
      # Disable `aldur.lazyvim.enable`.
      # jailed-lazyvim
    ];
  };
}
