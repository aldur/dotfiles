{ pkgs, ... }:
{
  home.packages = [ pkgs.neovim-bare ];
  home.sessionVariables = {
    MANPAGER = "nvim +Man!";
    EDITOR = "nvim";
  };
}
