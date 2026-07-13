# macOS-specific home-manager configuration
{
  config,
  pkgs,
  lib,
  ...
}:
let
  pythonWithTomlkit = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  mergeContainerConfig = ./merge-container-config.py;
in
{
  imports = [ ../home/home.nix ];

  home = {
    homeDirectory = "/Users/${config.home.username}";

    # macOS has no /run/user/$uid, so home-manager's tmux `secureSocket` is a
    # no-op here (tmux falls back to shared /tmp). Point TMUX_TMPDIR at the
    # per-user 0700 $TMPDIR (/var/folders/.../T) instead — the macOS analog of
    # the /run/user runtime dir secureSocket uses on Linux. (tmux enforces the
    # tmux-$uid subdir as 0700 owner-only regardless, so it's never exposed.)
    sessionVariables.TMUX_TMPDIR = "$TMPDIR";

    # Silence "Last login: ..."
    file.".hushlogin".text = "";

    # Don't mount $HOME into `container` VMs.
    activation.appleContainerConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config="$HOME/.config/container/config.toml"
      run mkdir -p "$(dirname "$config")"
      run ${pythonWithTomlkit}/bin/python3 ${mergeContainerConfig} "$config"
      run chmod 644 "$config"
    '';

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

  # Override the shared default (true): secureSocket points TMUX_TMPDIR at
  # /run/user/$uid, which macOS lacks; the sessionVariables override above
  # handles the per-user socket dir here instead.
  programs.tmux.secureSocket = false;
}
