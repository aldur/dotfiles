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

  coreutils = pkgs.coreutils;
  runuser = "${pkgs.util-linux}/bin/runuser";

  # Apple `container` boots a lightweight VM whose init runs this OCI image's
  # entrypoint as a single process — there is no systemd PID 1. So we apply the
  # NixOS + home-manager configuration ourselves at start.
  #
  # vminitd hands us an empty PATH, so every command is referenced by absolute
  # store path (and PATH is exported for the few that aren't).
  #
  # `exec "$@"` keeps the OCI Cmd overridable: `container run <img> <cmd>` still
  # activates first, then runs <cmd>.
  entrypoint = pkgs.writeShellScript "container-entrypoint" ''
    set -u
    export PATH=${coreutils}/bin:${pkgs.util-linux}/bin

    # No systemd here, so start the nix-daemon ourselves. Together with the
    # baked-in Nix DB (`includeNixDB` below) this makes `nix` usable inside the
    # container and — the reason it is required — lets home-manager activation
    # create its gcroots: it runs `nix-store --realise --add-root`, and the
    # NixOS environment sets NIX_REMOTE=daemon, so a daemon must be listening.
    mkdir -p /nix/var/nix/daemon-socket
    ${config.nix.package}/bin/nix-daemon &
    for _ in $(seq 1 100); do
      [ -S /nix/var/nix/daemon-socket/socket ] && break
      sleep 0.05
    done

    # System activation: /etc, /etc/passwd from the declarative users, tmpfiles.
    # The `specialfs` snippet tries to mount /proc,/dev,... which the runtime
    # already provides, so it warns and is skipped; `|| true` tolerates that.
    ln -sfn ${toplevel} /run/current-system
    ${toplevel}/activate || true

    # runuser resets PATH to a non-Nix default for the target user, so the
    # commands it runs are given by absolute path. home-manager activation
    # refuses to start unless a per-user Nix profile dir exists (normally made
    # by the daemon/PAM), so create it first. `--driver-version 1` matches the
    # NixOS home-manager unit (skips the redundant Nix-profile *update*).
    ${runuser} -u ${username} -- ${coreutils}/bin/mkdir -p /home/${username}/.local/state/nix/profiles
    ${runuser} -u ${username} -- ${hmActivate}/activate --driver-version 1 || true

    cd /home/${username}
    exec ${runuser} -u ${username} -- "$@"
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

  # Layered image built from the closure of `toplevel` (everything the
  # entrypoint references is pulled in automatically). `includeNixDB` registers
  # the store paths so the in-container nix-daemon treats them as valid (no
  # rebuild attempts, and home-manager's gcroots succeed).
  #
  # This is a `docker save`-format archive. Apple `container image load` wants
  # an OCI archive, so the README shows a one-line `skopeo` conversion — it runs
  # on the host (macOS has /var/tmp), which the Nix sandbox lacks, so it cannot
  # be baked into this derivation.
  system.build.containerImage = pkgs.dockerTools.buildLayeredImage {
    name = "aldur-nixos";
    tag = "latest";

    includeNixDB = true;

    # Mountpoints and writable dirs the runtime/activation expect; /tmp must
    # be world-writable+sticky so the unprivileged user (and nix) can use it.
    extraCommands = ''
      mkdir -p tmp proc sys dev etc run var home
      chmod 1777 tmp
    '';

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
