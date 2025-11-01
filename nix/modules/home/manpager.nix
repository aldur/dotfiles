{ pkgs, ... }:
{
  home.packages = with pkgs; [ neovim ];
  home.sessionVariables = {
    MANPAGER = "nvim +Man!";
    EDITOR = "nvim";
  };
}
