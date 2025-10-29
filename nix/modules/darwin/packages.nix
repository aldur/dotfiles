# macOS-specific configuration
{ pkgs, ... }:
with pkgs;
{
  environment.defaultPackages = [
    iterm2
  ];

  fonts.packages = [
    nerd-fonts.fira-code
  ];
}
