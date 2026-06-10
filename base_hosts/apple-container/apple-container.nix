{
  config,
  pkgs,
  lib,
  mkOciArchive,
  ...
}:
let
  username = "aldur";

  # Built straight from this evaluation — nothing here is re-listed.
  toplevel = config.system.build.toplevel;
  hmActivate = config.home-manager.users.${username}.home.activationPackage;
  shell = config.users.users.${username}.shell;

  inherit (pkgs) coreutils;
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

    # The daemon (and any nix client) fetches over TLS but nothing in this bare
    # environment points at a CA bundle, so set it explicitly. NixOS sets this
    # in /etc/set-environment for the login shell, but the daemon starts before
    # activation and wouldn't otherwise see it.
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-certificates.crt

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
    # `specialfs` is no-op'd (see config below) since the runtime already mounts
    # the API filesystems; `|| true` tolerates any remaining non-fatal snippet.
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
    # `runuser` starts a new session, which leaves the shell WITHOUT a
    # controlling terminal — and without one fish won't even source the user's
    # config (aliases like `lv`, the greeting, conf.d all silently skip). When
    # we have a tty, `--pty` gives the shell a real controlling terminal; for a
    # non-interactive `container run <img> <cmd>` we skip it so piped output
    # isn't mangled.
    if [ -t 0 ]; then
      exec ${runuser} --pty -u ${username} -- "$@"
    else
      exec ${runuser} -u ${username} -- "$@"
    fi
  '';
in
{
  imports = [ ./common.nix ];

  networking.hostName = "apple-container";

  # Apple's runtime already mounts /proc, /dev, /run, … into the container, so
  # NixOS's `specialfs` activation snippet only produces a wall of
  # `mount: … permission denied` warnings. No-op it (the snippets ordered after
  # it just need the mounts present, which they are). Other activation steps
  # (setup-etc, users, tmpfiles) still run. The full-system `apple-machine`
  # image leaves this alone: there systemd mounts them itself.
  system.activationScripts.specialfs = lib.mkForce "";

  # Layered image built from the closure of `toplevel` (everything the
  # entrypoint references is pulled in automatically). `includeNixDB` registers
  # the store paths so the in-container nix-daemon treats them as valid (no
  # rebuild attempts, and home-manager's gcroots succeed).
  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos";
    layered = pkgs.dockerTools.buildLayeredImage {
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
  };
}
