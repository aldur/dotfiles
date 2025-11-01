# macOS-specific home-manager configuration
{ config, ... }:
{
  imports = [ ../home/home.nix ];

  home.homeDirectory = "/Users/${config.home.username}";

  # Silence "Last login: ..."
  home.file.".hushlogin".text = "";
}
