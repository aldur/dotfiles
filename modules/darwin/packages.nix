# macOS-specific configuration
{ pkgs, ... }:
with pkgs;
{
  environment.defaultPackages = [
    yubikey-agent
  ];

  fonts.packages = [
    nerd-fonts.fira-code
  ];
}
