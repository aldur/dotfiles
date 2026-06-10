{
  config,
  pkgs,
  ...
}:
let
  username = "aldur";

  # Built straight from this evaluation — nothing here is re-listed.
  toplevel = config.system.build.toplevel;
  hmActivate = config.home-manager.users.${username}.home.activationPackage;
  shell = config.users.users.${username}.shell;

  # Apple `container` boots a lightweight VM whose init runs this OCI image's
  # entrypoint as a single process — there is no systemd PID 1. So we apply the
  # NixOS + home-manager configuration ourselves at start: point
  # /run/current-system at the toplevel, run the system activation (sets up
  # /etc, /etc/passwd from the declarative users, tmpfiles), then the
  # home-manager activation for the user (materializes ~/.config: fish, lazyvim,
  # git, claude-code). systemctl-touching activation snippets self-skip without
  # /run/systemd/system; `|| true` tolerates the remaining warnings.
  #
  # `exec "$@"` keeps the OCI Cmd overridable: `container run <img> <cmd>` still
  # activates first, then runs <cmd>.
  entrypoint = pkgs.writeShellScript "container-entrypoint" ''
    set -u
    ln -sfn ${toplevel} /run/current-system
    ${toplevel}/activate || true

    # home-manager activation refuses to run unless a per-user Nix profile
    # directory exists (normally created by the daemon/PAM). There is none
    # here, so create the one it looks for first. `--driver-version 1` then
    # matches the NixOS home-manager unit: it skips the Nix-profile *update*,
    # the only step that needs the (absent) nix-daemon. Together these let the
    # dotfiles/lazyvim/claude-code config link with no daemon at all.
    run() { ${pkgs.util-linux}/bin/runuser -u ${username} -- "$@"; }
    run mkdir -p /home/${username}/.local/state/nix/profiles
    run ${hmActivate}/activate --driver-version 1 || true

    cd /home/${username}
    exec ${pkgs.util-linux}/bin/runuser -u ${username} -- "$@"
  '';
in
{
  # We are a container, not a VM/host: drop kernel/initrd and hardware units
  # from the closure.
  boot.isContainer = true;

  networking.hostName = "apple-container";

  # There is no sshd or login manager here — access is via `container run`,
  # which drops straight into the activated user (see the entrypoint). So no
  # account needs a password; say so explicitly rather than be "locked out".
  users.allowNoPasswordLogin = true;

  programs = {
    aldur = {
      lazyvim.enable = true;
      lazyvim.packageNames = [ "lazyvim" ];

      claude-code.enable = true;
    };
  };

  home-manager.users.${username} = _: {
    programs = {
      git.settings.gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | grep -i sign)'";
      better-nix-search.enable = true;
    };
  };

  # A single-layer OCI archive built from the closure of `toplevel` (everything
  # the entrypoint references is pulled in automatically). `result` is a
  # gzipped `docker save`-format archive, loadable with `container image load`.
  system.build.containerImage = pkgs.dockerTools.buildLayeredImage {
    name = "aldur-nixos";
    tag = "latest";

    # Mountpoints and writable dirs the runtime/activation expect to exist.
    extraCommands = "mkdir -p tmp proc sys dev etc run var home";

    config = {
      Entrypoint = [ "${entrypoint}" ];
      Cmd = [
        "${shell}/bin/fish"
        "-l"
      ];
      WorkingDir = "/home/${username}";
      Env = [ "TERM=screen-256color" ];
    };
  };
}
