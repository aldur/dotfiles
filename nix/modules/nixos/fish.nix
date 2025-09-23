{ pkgs, ... }:
{
  documentation.man.generateCaches = false;
  users.defaultUserShell = pkgs.fish;
}
