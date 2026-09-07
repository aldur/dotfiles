# When NixOS `programs.direnv` is enabled, it sets DIRENV_CONFIG=/etc/direnv,
# which makes direnv ignore ~/.config/direnv/direnv.toml (where home-manager
# writes its config). This module ensures /etc/direnv/direnv.toml is created
# with the same settings so they apply regardless of which level enables
# direnv.
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.programs.direnv.enable {
  programs.direnv.settings = import ../shared/programs/direnv;
  programs.direnv.direnvrcExtra = import ../shared/programs/direnv/stdlib.nix { inherit pkgs; };
}
