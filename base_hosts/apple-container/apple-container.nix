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
    # Hand off to the user's shell with a *controlling terminal* — fish needs one
    # to source its interactive config (`lv`, the greeting, conf.d). The runtime
    # gives PID 1 a tty either way, but not always as a controlling terminal:
    #   - docker/podman make it PID 1's controlling terminal → plain `runuser`
    #     (which doesn't start a new session) inherits it.
    #   - Apple `container run` gives a tty with NO controlling terminal → we
    #     claim the (unclaimed) pty in a new session with `setsid -c`. That needs
    #     no capability (claiming an unclaimed tty isn't stealing), and unlike
    #     `runuser --pty` it adds no I/O proxy, so an activation orphan dying
    #     can't wedge the session. Both paths verified locally.
    # Non-interactive `container run <img> <cmd>` (no tty) just runs <cmd>.
    if [ -t 0 ] && ! (: >/dev/tty) 2>/dev/null; then
      exec ${pkgs.util-linux}/bin/setsid -c -w ${runuser} -u ${username} -- "$@"
    else
      exec ${runuser} -u ${username} -- "$@"
    fi
  '';
in
{
  imports = [ ./common.nix ];

  networking.hostName = "nixos-apple-container";

  # Make `specialfs` tolerant rather than no-op'd: skip what the runtime already
  # mounted (so `container run` startup stays quiet — no `mount: … permission
  # denied` spam), and mount/tolerate the rest, which is what systemd needs when
  # the same image boots via `/sbin/init` under `container machine`.
  system.activationScripts.specialfs = lib.mkForce ''
    specialMount() {
      local device="$1" mountPoint="$2" options="$3" fsType="$4"
      mountpoint -q "$mountPoint" && return 0
      mkdir -p "$mountPoint" && chmod 0755 "$mountPoint"
      mount -t "$fsType" -o "$options" "$device" "$mountPoint" 2>/dev/null || true
    }
    source ${config.system.build.earlyMountScript}
  '';

  # `container machine`'s bootstrap writes /etc/resolv.conf and /etc/hosts before
  # the guest boots; vminitd assigns the IP/route. So don't run DHCP and don't
  # let resolvconf replace /etc/resolv.conf afterwards.
  networking.useDHCP = false;
  networking.resolvconf.enable = lib.mkForce false;

  # One artifact, two entry doors into the same system closure:
  #   - `container run`  uses the OCI Entrypoint → activation → fish.
  #   - `container machine` ignores the OCI config and execs /sbin/init →
  #     the NixOS stage-2 init → systemd as PID 1.
  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos";
    stream = pkgs.dockerTools.streamLayeredImage {
      name = "aldur-nixos";
      tag = "latest";

      includeNixDB = true;

      # /sbin/init for `container machine`; real (placeholder) /etc files so /etc
      # is a guaranteed-present writable dir its bootstrap can write into (empty
      # dirs can be dropped in OCI conversion); /tmp world-writable+sticky.
      extraCommands = ''
        mkdir -p sbin tmp proc sys dev etc run var home
        ln -sfn ${toplevel}/init sbin/init
        : > etc/resolv.conf
        printf '127.0.0.1 localhost\n' > etc/hosts
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
