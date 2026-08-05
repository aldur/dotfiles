{ pkgs, lib, ... }:
{
  # Hand-rolled equivalent of programs.neovim.enable + defaultEditor,
  # to keep things lean.
  environment.systemPackages = [ pkgs.neovim-bare ];
  environment.variables.EDITOR = lib.mkOverride 900 "nvim"; # Same strength defaultEditor uses.
}
