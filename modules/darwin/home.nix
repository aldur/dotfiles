# macOS-specific home-manager configuration
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [ ../home/home.nix ];

  # home-manager builds `man home-configuration.nix` with its own nixpkgs, so the
  # store-path scrub overlay must be applied here too — the system overlay in
  # darwin/nixpkgs.nix does not reach it.
  nixpkgs.overlays = [
    (import ../../overlays/darwin/options-doc-links.nix { inherit inputs; })
  ];

  home = {
    homeDirectory = "/Users/${config.home.username}";

    # Silence "Last login: ..."
    file.".hushlogin".text = "";

    shellAliases = {
      tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";

      faraday = "sandbox-exec -p '(version 1)(allow default)(deny network*)'";
      sandbox = "sandbox-exec -p '(version 1)(allow default)(deny network*)(deny file-read-data (regex \"^/Users/'$USER'/(Documents|Desktop|Developer|Movies|Music|Pictures)\"))'";
    };

    packages = with pkgs; [
      reattach-to-user-namespace
    ];
  };

  services.gpg-agent = {
    pinentry.package = pkgs.pinentry_mac;
  };
}
