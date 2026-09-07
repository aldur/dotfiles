{ pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    stdlib = import ../shared/programs/direnv/stdlib.nix { inherit pkgs; };
    nix-direnv.enable = true;
    config = import ../shared/programs/direnv;
  };
}
