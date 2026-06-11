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

  inherit (pkgs) coreutils;
  runuser = "${pkgs.util-linux}/bin/runuser";

  # aldur's login shell, both in the baked /etc/passwd and the NixOS user
  # declaration: Apple's `container machine` opens its session
  # (`/sbin.machine/init -s`) as soon as the container starts, racing NixOS
  # first-boot activation AND the home-manager service (observed, separate
  # runs: nameless uid 501 with bare PATH; "/run/current-system/sw/bin/fish:
  # No such file or directory" from passwd already rewritten but the symlink
  # not yet made; fish up but greeting/config missing and ~/.config created
  # group-`lp` by the gid-20 session). Wait for both, then a login fish.
  # ~/.config/fish/config.fish is the home-manager completion marker; if fish
  # ever stops being home-managed, sessions eat the 60s timeout — adjust then.
  # A bin-in-package path (not a bare store file): NixOS' toShellPath rejects
  # plain store paths as login shells, but passes path strings through.
  machineSessionShell = "${pkgs.writeShellScriptBin "machine-session-shell" ''
    for _ in $(${coreutils}/bin/seq 1 600); do
      [ -x /run/current-system/sw/bin/fish ] \
        && [ -e "$HOME"/.config/fish/config.fish ] \
        && break
      ${coreutils}/bin/sleep 0.1
    done
    exec /run/current-system/sw/bin/fish -l "$@"
  ''}/bin/machine-session-shell";

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
    # cacert ships ca-bundle.crt — the previous ca-certificates.crt name
    # dangled, and `nix` died with "error adding trust anchors" on any TLS use
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    # Activation runs to logs, and failures are *loud*: `|| true` used to swallow
    # them, which left Apple-only failures (not reproducible under podman)
    # looking like shell-config bugs — fish without its home-manager config
    # still prints the default greeting and lacks `lv`.
    logdir=/var/log/entrypoint
    mkdir -p "$logdir"
    fail() {
      printf '\033[1;31mentrypoint: %s — full log: %s\033[0m\n' "$1" "$2"
      tail -n 15 "$2" 2>/dev/null
    }

    mkdir -p /nix/var/nix/daemon-socket
    # Detach the daemon from the controlling terminal. Otherwise it inherits the
    # container's tty, fish's terminal setup a moment after launch HUPs it, and
    # its death (it's a child of the `runuser --pty` proxy that is PID 1) wedges
    # the interactive session — input stops being forwarded. `setsid` + /dev/null
    # fully detaches it.
    ${pkgs.util-linux}/bin/setsid ${config.nix.package}/bin/nix-daemon \
      </dev/null >"$logdir/nix-daemon.log" 2>&1 &
    for _ in $(seq 1 200); do
      [ -S /nix/var/nix/daemon-socket/socket ] && break
      sleep 0.05
    done
    [ -S /nix/var/nix/daemon-socket/socket ] \
      || fail "nix-daemon socket missing after 10s" "$logdir/nix-daemon.log"

    ln -sfn ${toplevel} /run/current-system
    ${toplevel}/activate >"$logdir/system-activation.log" 2>&1 \
      || fail "system activation failed" "$logdir/system-activation.log"

    # vminitd names the UTS namespace after the container ID (the OCI spec
    # default) and no systemd runs in this door to apply networking.hostName —
    # do it ourselves. Tolerated if the runtime withholds CAP_SYS_ADMIN.
    echo ${lib.escapeShellArg config.networking.hostName} > /proc/sys/kernel/hostname 2>/dev/null \
      || true

    ${runuser} -u ${username} -- ${coreutils}/bin/mkdir -p /home/${username}/.local/state/nix/profiles
    # Preflight the daemon as the user, with errors VISIBLE. Home-manager's
    # `activate` is `set -e` and wraps its first daemon write —
    # `nix-store --realise <gen> --add-root …` — in `run --silence`, so when
    # that dies the log ends at the banner with no error at all (observed on
    # Apple). Mirror the same query + realise + indirect-gc-root here.
    {
      ${runuser} -u ${username} -- ${config.nix.package}/bin/nix-store -q --hash ${hmActivate} \
        && ${runuser} -u ${username} -- ${config.nix.package}/bin/nix-store --realise ${hmActivate} \
          --add-root /tmp/.hm-preflight-root
    } >"$logdir/nix-preflight.log" 2>&1 || {
      fail "nix daemon preflight failed (home-manager activation will too)" "$logdir/nix-preflight.log"
      fail "nix-daemon's own log" "$logdir/nix-daemon.log"
    }
    ${runuser} -u ${username} -- ${hmActivate}/activate --driver-version 1 \
      >"$logdir/home-manager.log" 2>&1 \
      || fail "home-manager activation failed" "$logdir/home-manager.log"

    if [ "''${CONTAINER_DEBUG:-}" = 1 ]; then
      echo "== entrypoint debug =="
      [ -t 0 ] && echo "fd0 is a tty: yes" || echo "fd0 is a tty: no"
      (: >/dev/tty) 2>/dev/null && echo "PID1 has a ctty: yes" || echo "PID1 has a ctty: no"
      echo "fd0 -> $(readlink /proc/$$/fd/0 2>/dev/null)"
      echo "PID1 tty_nr: $(cut -d' ' -f7 /proc/1/stat 2>/dev/null)"
    fi

    cd /home/${username}
    # Hand off to the user's shell. Both Apple `container` (vmexec's childSetup
    # does setsid() + ioctl(TIOCSCTTY) before exec'ing us — see
    # containerization vminitd/Sources/vmexec/RunCommand.swift) and podman give
    # PID 1 the pty as a *controlling* terminal, so plain `runuser` (no new
    # session) inherits it and fish gets job control. The `setsid -c` branch is
    # a safety net for a runtime that hands us a tty without claiming it; unlike
    # `runuser --pty` it adds no I/O proxy that an activation orphan's death
    # could wedge.
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

  # `container machine` opens its shell as the *Mac* uid (CONTAINER_UID, 501
  # for the first macOS user) and the shared /Users files carry it too. Pin
  # aldur to that uid so `id -un` resolves, the exec picks HOME/SHELL from
  # /etc/passwd (observed otherwise: nameless uid 501, HOME=/, default sh),
  # and the virtiofs-shared files are owned by aldur inside the guest.
  # NixOS asserts `isNormalUser` ⇒ uid ≥ 1000, so take its prescribed escape
  # hatch (isSystemUser) and re-state what isNormalUser implied.
  users.users.${username} = {
    uid = 501;
    isNormalUser = lib.mkForce false;
    isSystemUser = true;
    group = "users";
    home = "/home/${username}";
    createHome = true;
    # The wait-for-boot wrapper (not plain fish, mkForce'd over the shared
    # modules' choice): the machine session can fire inside activation, after
    # /etc/passwd is rewritten but before /run/current-system or the
    # home-manager files exist. Keeping the wrapper as the *declared* shell
    # closes that window for every session, and pulls it into the image
    # closure via the toplevel.
    shell = lib.mkForce "${machineSessionShell}";
  };

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

  # `container machine` opens its shell (`/sbin.machine/init -s`) as plain
  # non-login fish outside any PAM session, so nothing has applied the NixOS
  # session environment — PATH is bare FHS and every command is "not found".
  # The stock /etc/fish/nixos-env-preinit.fish exists for exactly this job and
  # self-guards with $__NIXOS_SET_ENVIRONMENT_DONE; vendor conf.d runs after
  # fish's embedded config has set fish_function_path, which the preinit
  # clobbers and erases (it expects to run first), so save/restore it.
  environment.etc."fish/conf.d/nixos-env.fish".text = ''
    if test -z "$__NIXOS_SET_ENVIRONMENT_DONE"; and test -r /etc/fish/nixos-env-preinit.fish
        set -l __saved_function_path $fish_function_path
        source /etc/fish/nixos-env-preinit.fish
        set -g fish_function_path $__saved_function_path
    end
  '';

  # One artifact, two entry doors into the same system closure:
  #   - `container run`  uses the OCI Entrypoint → activation → fish.
  #   - `container machine` ignores the OCI config and execs /sbin/init →
  #     the NixOS stage-2 init → systemd as PID 1.
  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos";
    stream = pkgs.dockerTools.streamLayeredImage {
      name = "aldur-nixos";
      tag = "latest";

      # /sbin/init for `container machine`; real (placeholder) /etc files so /etc
      # is a guaranteed-present writable dir its bootstrap can write into (empty
      # dirs can be dropped in OCI conversion); /tmp world-writable+sticky.
      #
      # `container machine` boots Apple's /sbin.machine/init — a `#!/bin/sh`
      # script virtiofs-mounted from the host bundle (apple/container
      # Sources/Plugins/MachineAPIServer/Resources/init). exec'ing it in a bare
      # NixOS rootfs fails with ENOENT: the shebang interpreter /bin/sh doesn't
      # exist. The script is `set -e`, sources /etc/os-release (a missing file
      # kills a POSIX sh outright), uses id/grep/cut to open the user's shell
      # (`-s`) and chown for $SSH_AUTH_SOCK — so ship those at FHS paths, plus
      # os-release. Its first-boot provisioning (`-u`) is overridable via
      # /etc/machine/create-user.sh: ours is a no-op, NixOS declares the user.
      extraCommands = ''
        mkdir -p sbin tmp proc sys dev etc/machine run var home bin usr/bin
        ln -sfn ${toplevel}/init sbin/init
        : > etc/resolv.conf
        printf '127.0.0.1 localhost\n' > etc/hosts
        ln -s ${config.environment.etc."os-release".source} etc/os-release
        for d in bin usr/bin; do
          ln -s ${config.environment.binsh} "$d"/sh
          ln -s ${pkgs.bashInteractive}/bin/bash "$d"/bash
          ln -s ${pkgs.gnugrep}/bin/grep "$d"/grep
          for b in ${coreutils}/bin/*; do
            ln -s "$b" "$d"/"''${b##*/}"
          done
        done
        # Pre-activation /etc/passwd + /etc/group (first-boot machine sessions
        # exec before activation writes the real ones; uid/gid match the NixOS
        # declaration, and mutableUsers=false rewrites these wholesale at
        # activation). aldur's shell is the wait-for-activation wrapper.
        cat > etc/passwd <<'EOF'
        root:x:0:0:root:/root:/bin/sh
        ${username}:x:501:100::/home/${username}:${machineSessionShell}
        EOF
        cat > etc/group <<'EOF'
        root:x:0:
        users:x:100:
        EOF
        cat > etc/machine/create-user.sh <<'EOF'
        #!/bin/sh
        # NixOS declares the machine user; nothing to provision on first boot.
        exit 0
        EOF
        chmod +x etc/machine/create-user.sh
        chmod 1777 tmp
        # Register the shipped closure in the image's nix DB. This was Bug 1's
        # root cause: dockerTools' `includeNixDB` registers only the closure of
        # `contents` (empty here — symlinkJoin would merge its entries into the
        # image root), so the DB shipped EMPTY and home-manager's first daemon
        # operation, the output-silenced `nix-store --realise <generation>`,
        # died with "path … is not valid" right after its banner.
        export NIX_REMOTE="local?root=$PWD" USER=nobody
        ${lib.getExe' pkgs.buildPackages.nix "nix-store"} --load-db < ${
          pkgs.closureInfo {
            rootPaths = [
              toplevel
              hmActivate
            ];
          }
        }/registration
        # Reset registration times to keep the image reproducible
        ${lib.getExe pkgs.buildPackages.sqlite} nix/var/nix/db/db.sqlite \
          "UPDATE ValidPaths SET registrationTime = ''${SOURCE_DATE_EPOCH}"
        # In-image GC roots for the two generations (a `nix-collect-garbage`
        # inside the container must not eat the system it runs on)
        mkdir -p nix/var/nix/gcroots/docker
        ln -s ${toplevel} ${hmActivate} nix/var/nix/gcroots/docker/
      '';

      config = {
        Entrypoint = [ "${entrypoint}" ];
        # The same wait-wrapper the machine sessions use; under `container run`
        # the entrypoint has already finished both activations, so it execs a
        # login fish immediately.
        Cmd = [ "${machineSessionShell}" ];
        WorkingDir = "/home/${username}";
        Env = [ "TERM=screen-256color" ];
      };
    };
  };
}
