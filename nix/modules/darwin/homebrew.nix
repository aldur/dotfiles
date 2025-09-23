{
  inputs,
  config,
  user,
  ...
}:
{
  imports = [
    ./casks.nix
    ./masApps.nix
  ];

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";

    caskArgs.no_quarantine = true;
    caskArgs.require_sha = true;

    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  nix-homebrew = {
    # User owning the Homebrew prefix
    inherit user;

    # Install Homebrew under the default prefix
    enable = true;

    # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
    enableRosetta = true;

    # Automatically migrate existing Homebrew installations
    autoMigrate = true;

    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };

    # Optional: Enable fully-declarative tap management
    #
    # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    mutableTaps = false;

    # Disable this so that homebrew executables don't get on our PATH
    # (we only use homebrew for casks anyway)
    enableFishIntegration = false;
    enableBashIntegration = false;
    enableZshIntegration = false;
  };
  environment.variables = {
    HOMEBREW_NO_INSECURE_REDIRECT = "1";
    HOMEBREW_CASK_OPTS = "--require-sha";
    HOMEBREW_NO_AUTO_UPDATE = "1";
    HOMEBREW_NO_ANALYTICS = "1";
  };
}
