{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  programs = {
    # Set to true to enable homebrew integration.
    homebrew.enable = false;

    # Set to true if you want to use Determinate Nix
    determinate-nix.enable = false;
  };

  # To enable the smarter Linux builder:
  #
  # 1. Set
  # nix.linux-builder.enable = true;
  # 2. Rebuild
  # 3. Set
  # nix.linux-builder.enable = false;
  # 4. Set `services.linux-builder.enable` to true.
  services.linux-builder.enable = false;

  # Then, add brews, casks, and masApps here
  homebrew = {
    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.masApps
    masApps = { };

    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.brews
    brews = [ ];

    casks = [ ];
  };

  home-manager.users.aldur = _: {
    # SSH agent backed by a YubiKey (launchd agent listening on
    # /tmp/yubikey-agent.sock). Shells pick up SSH_AUTH_SOCK from it unless
    # an agent is forwarded in over SSH.
    services.yubikey-agent.enable = true;

    programs.aldur = {
      lazyvim.enable = true;
      lazyvim.packageNames = [ "lazyvim" ];
    };

    home.packages = with pkgs; [
      git-crypt

      # In case you want to jail lazyvim
      # Disable `aldur.lazyvim.enable`.
      # jailed-lazyvim
    ];
  };
}
