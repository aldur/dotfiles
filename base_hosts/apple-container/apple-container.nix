{
  config,
  pkgs,
  lib,
  mkOciArchive,
  ...
}:
let
  username = "aldur";

  toplevel = config.system.build.toplevel;
  hmActivate = config.home-manager.users.${username}.home.activationPackage;
  shell = config.users.users.${username}.shell;

  inherit (pkgs) coreutils;
  runuser = "${pkgs.util-linux}/bin/runuser";

  # Apple `container` boots a lightweight VM whose init runs this OCI image's
  # entrypoint as a single process — there is no systemd PID 1.
  # We apply the NixOS + home-manager configuration ourselves at start.
  #
  # vminitd hands us an empty PATH, so every command is referenced by absolute
  # store path (and PATH is exported for the few that aren't).
  #
  # `exec "$@"` keeps the OCI Cmd overridable: `container run <img> <cmd>` still
  # activates first, then runs <cmd>.
  entrypoint = pkgs.writeShellScript "container-entrypoint" ''
    set -u
    export PATH=${coreutils}/bin:${pkgs.util-linux}/bin
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-certificates.crt

    mkdir -p /nix/var/nix/daemon-socket
    # Detach the daemon from the controlling terminal. Otherwise it inherits the
    # container's tty, fish's terminal setup a moment after launch HUPs it, and
    # its death (it's a child of the `runuser --pty` proxy that is PID 1) wedges
    # the interactive session — input stops being forwarded. `setsid` + /dev/null
    # fully detaches it (and drops the "accepted connection" noise).
    ${pkgs.util-linux}/bin/setsid ${config.nix.package}/bin/nix-daemon </dev/null >/dev/null 2>&1 &
    for _ in $(seq 1 100); do
      [ -S /nix/var/nix/daemon-socket/socket ] && break
      sleep 0.05
    done

    ln -sfn ${toplevel} /run/current-system
    ${toplevel}/activate || true

    ${runuser} -u ${username} -- ${coreutils}/bin/mkdir -p /home/${username}/.local/state/nix/profiles
    ${runuser} -u ${username} -- ${hmActivate}/activate --driver-version 1 || true

    cd /home/${username}
    # Hand off to the user's shell with a *controlling terminal*. `runuser --pty`
    # proxies I/O and wedged the session as PID 1; `setsid --ctty` can't steal
    # the tty once we've dropped privileges. `login` does the privileged tty
    # setup as root and *then* drops to the user — the exact path getty uses,
    # which works in the qemu VM. It runs the user's login shell from
    # /etc/passwd (fish) in a clean login environment. The non-interactive case
    # keeps `runuser` so `container run <img> <cmd>` still runs <cmd>.
    if [ -t 0 ]; then
      exec ${pkgs.shadow}/bin/login -f ${username}
    else
      exec ${runuser} -u ${username} -- "$@"
    fi
  '';
in
{
  imports = [ ./common.nix ];

  networking.hostName = "nixos-apple-container";

  system.activationScripts.specialfs = lib.mkForce "";

  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos";
    stream = pkgs.dockerTools.streamLayeredImage {
      name = "aldur-nixos";
      tag = "latest";

      includeNixDB = true;

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
