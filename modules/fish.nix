{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [ ./shared/options.nix ];

  # Enable vendoring fish completions provided by Nixpkgs.
  #
  # See https://github.com/LnL7/nix-darwin/issues/122#issuecomment-1782971499
  # if this doesn't work at first on `nix-darwin`.
  programs.fish.enable = true;

  users.users = lib.genAttrs config.interactiveUsers (_: {
    shell = pkgs.fish;
  });
}
