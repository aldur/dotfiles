{ config, pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  programs = {
    # Set to true to enable homebrew integration.
    homebrew.enable = false;

    # Set to true if you want to use Determinate Nix
    determinate-nix.enable = false;
  };

  # Builders default to disabled; enable it here.
  # The standard builder can bootstrap from the binary cache on a fresh Mac.
  nix.linux-builder.enable = false;

  # To switch to the Rosetta builder (also supports x86_64-linux), rebuild
  # once with the standard builder, then set nix.linux-builder.enable = false
  # and services.linux-builder.enable = true before rebuilding again.
  services.linux-builder.enable = false;

  # Coding agents; see modules/home/claude and modules/home/codex.
  # The -yolo scripts run on the host here (the bubblewrap wrapper is Linux-only).
  programs.aldur = {
    claude-code.enable = true;
    codex.enable = true;
  };

  # Then, add brews, casks, and masApps here
  homebrew = {
    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.masApps
    masApps = { };

    # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-homebrew.brews
    brews = [ ];

    casks = [ ];
  };

  home-manager.users.${config.mainUser} = _: {
    # SSH agent backed by a YubiKey (launchd agent listening on
    # /tmp/yubikey-agent.sock). Shells pick up SSH_AUTH_SOCK from it unless
    # an agent is forwarded in over SSH.
    services.yubikey-agent.enable = true;

    programs.aldur.lazyvim.enable = true;

    home.packages = with pkgs; [
      git-crypt

      # In case you want to jail lazyvim
      # Disable `aldur.lazyvim.enable`.
      # jailed-lazyvim
    ];
  };
}
