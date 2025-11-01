# macOS-specific home-manager configuration
{ config, ... }: {
  imports = [ ../home/home.nix ];

  home.homeDirectory = "/Users/${config.home.username}";

  # Silence "Last login: ..."
  home.file.".hushlogin".text = "";

  home.shellAliases = {
    tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";

    faraday = "sandbox-exec -p '(version 1)(allow default)(deny network*)'";
    sandbox =
      "sandbox-exec -p '(version 1)(allow default)(deny network*)(deny file-read-data (regex \"^/Users/'$USER'/(Documents|Desktop|Developer|Movies|Music|Pictures)\"))'";
  };
}
