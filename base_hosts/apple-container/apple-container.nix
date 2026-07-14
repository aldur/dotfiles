# Generic support for running NixOS under Apple `container`
# (https://github.com/apple/container). One image, two entry doors:
#   - `container run`     → OCI Entrypoint → activation → login shell
#   - `container machine` → Apple's /sbin.machine/init → /sbin/init → systemd
# Site-specific values come in through the `virtualisation.appleContainer`
# options; build the image from `config.system.build.containerImage`.
{
  config,
  options,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.virtualisation.appleContainer;
  inherit (cfg) username uid;

  # The shell the site config *declared* for the user (users.users.<name>.shell
  # = pkgs.fish in the consumer's own modules). We mkForce that very option to
  # the session wrapper below, so the declaration can't be read back from
  # `config` — recover it from the raw option definitions instead, skipping
  # our own (override-marked) one. Falls back to bash when nothing declares it.
  declaredUserShell =
    let
      defs = lib.concatMap (
        def: lib.optional (def ? ${username} && def.${username} ? shell) def.${username}.shell
      ) options.users.users.definitions;
      external = lib.filter (v: (v._type or null) != "override") defs;
    in
    if external == [ ] then pkgs.bashInteractive else lib.head external;

  toplevel = config.system.build.toplevel;
  # Home-manager is optional for consumers of this module; every HM step is
  # skipped when the user isn't home-managed.
  hasHomeManager = config ? home-manager && config.home-manager.users ? ${username};
  hmActivate = config.home-manager.users.${username}.home.activationPackage;

  inherit (pkgs) coreutils;
  runuser = "${pkgs.util-linux}/bin/runuser";

  # Apple's /sbin.machine/init is `#!/bin/sh` and vminitd execs it with an empty
  # PATH. NixOS bash falls back to `/no-such-path` (a purity measure), so the
  # init's unqualified `id`/`grep`/`cut` (resolving the session shell from
  # /etc/passwd, `-s` branch only — the boot branch uses just builtins, which is
  # why machines boot while sessions break) fail; under `--root` that leaves
  # USER_SHELL empty and the session exits 127. Make /bin/sh a thin wrapper that
  # *appends* a fallback PATH (any inherited PATH still wins, so only the
  # empty-PATH case changes) before handing off to the real shell.
  #
  # The fallback points at the coreutils/gnugrep *store paths*, not /bin: post-
  # boot envfs owns /bin, and envfs resolves each lookup from the *calling
  # process's* /proc/<pid>/environ — it consults its fallback-path dir (sh/env
  # only) solely when that environ carries no PATH at all, and skips /bin and
  # /usr/bin PATH entries to dodge recursion. So the moment a wrapper exports
  # PATH=/bin:/usr/bin, nothing resolves through /bin anymore (verified live);
  # store paths resolve in every mount/boot state. Wired through
  # `environment.binsh` below (not just the image symlink) because envfs serves
  # /bin/sh from a fallback-path built from that option — it's the only knob
  # governing /bin/sh.
  #
  # Testing trap: `env -i /bin/sh -c …` does NOT reproduce the empty-PATH case —
  # /proc/<pid>/environ is frozen at exec, so envfs still sees `env`'s inherited
  # full PATH and serves whatever `sh` that PATH reaches (the plain sw/bin one),
  # bypassing this wrapper. Faithful reproduction, mirroring how vminitd (empty
  # environ) execs the init:
  #   env -i "$(readlink -f /run/current-system/sw/bin/bash)" \
  #     -c 'exec /bin/sh -c "id -un"'
  binSh = pkgs.writeShellScript "container-bin-sh" ''
    export PATH="''${PATH:+$PATH:}${coreutils}/bin:${pkgs.gnugrep}/bin:/bin:/usr/bin"
    exec ${pkgs.bashInteractive}/bin/sh "$@"
  '';

  shellBin = baseNameOf (lib.getExe cfg.shell);
  runtimeShell = "/run/current-system/sw/bin/${shellBin}";

  # Login-shell wrapper for machine sessions, used as the declared shell for
  # BOTH the interactive user and root. Apple's `container machine` opens its
  # session (`/sbin.machine/init -s`) as soon as the container starts, racing
  # NixOS first-boot activation AND the home-manager service (observed, separate
  # runs: nameless uid with bare PATH; "…/fish: No such file or directory" from
  # passwd already rewritten but the symlink not yet made; shell up but its
  # config missing). Wait for what's needed, then exec a login shell. The bare
  # declaration produces /run/current-system/sw/bin/<shell>, which doesn't exist
  # until activation finishes — so `container machine run --root` (root's shell)
  # hits exactly that race without this wrapper. A bin-in-package path (not a
  # bare store file): NixOS' toShellPath rejects plain store paths as login
  # shells, but passes path strings through.
  mkSessionShell =
    {
      name,
      user,
      waitForHomeManager,
    }:
    "${pkgs.writeShellScriptBin name ''
    ready() {
      [ -x ${runtimeShell} ] || return 1
      ${lib.optionalString (
        waitForHomeManager && cfg.homeManagerMarker != null
      ) ''[ -e "$HOME"/${lib.escapeShellArg cfg.homeManagerMarker} ] || return 1''}
      return 0
    }
    for _ in $(${coreutils}/bin/seq 1 600); do
      ready && break
      ${coreutils}/bin/sleep 0.1
    done
    # We run outside any PAM session (Apple execs the session directly), so
    # nothing has applied the NixOS session environment — without this, PATH
    # stays bare FHS and every command is "not found", whatever the shell.
    # /etc/set-environment is bash syntax (it's what /etc/profile sources),
    # self-guards with __NIXOS_SET_ENVIRONMENT_DONE, and the exec'd shell
    # inherits the result. USER/LOGNAME first: it builds PATH entries like
    # /etc/profiles/per-user/$USER/bin from them, and login(1) would have set
    # them anyway.
    export USER=${user} LOGNAME=${user}
    [ -z "''${__NIXOS_SET_ENVIRONMENT_DONE:-}" ] && [ -r /etc/set-environment ] \
      && . /etc/set-environment
    # `nix shell`/`nix develop` spawn $SHELL and fall back to literal "bash"
    # when it's unset — observed dropping the user into bash. We're the login
    # shell, so claim the variable like login(1) would.
    export SHELL=${runtimeShell}
    # …same for XDG_RUNTIME_DIR: point it at the user manager's directory
    # when present (lingering creates it at boot; the run-door entrypoint
    # mkdirs it).
    d=/run/user/$(${coreutils}/bin/id -u)
    [ -d "$d" ] && export XDG_RUNTIME_DIR="$d"
    # Apple's machine sessions arrive with TERM unset or a hardcoded plain
    # `xterm` (8 colors — a lie for every modern macOS terminal); upgrade
    # those. SSH sessions land in this wrapper too, but sshd forwards the
    # *client's* real TERM — never second-guess it, even if it's `xterm`.
    if [ -z "''${SSH_CONNECTION:-}" ]; then
      case "''${TERM:-}" in
        "" | xterm) export TERM=xterm-256color ;;
      esac
    fi
    exec ${runtimeShell} -l "$@"
  ''}/bin/${name}";

  # The interactive user also waits for home-manager (its shell config lives
  # there); root has no home-manager, so it waits only for the system shell.
  machineSessionShell = mkSessionShell {
    name = "machine-session-shell";
    user = username;
    waitForHomeManager = true;
  };
  rootSessionShell = mkSessionShell {
    name = "root-session-shell";
    user = "root";
    waitForHomeManager = false;
  };

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
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    logdir=/var/log/entrypoint
    mkdir -p "$logdir"
    fail() {
      printf '\033[1;31mentrypoint: %s — full log: %s\033[0m\n' "$1" "$2"
      tail -n 15 "$2" 2>/dev/null
    }

    mkdir -p /nix/var/nix/daemon-socket
    # Detach the daemon from the controlling terminal.
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
    # default) and no systemd runs to apply a hostname, so set the configured
    # one ourselves. Tolerated if the runtime withholds CAP_SYS_ADMIN.
    ${lib.optionalString (cfg.hostName != "") ''
      echo ${lib.escapeShellArg cfg.hostName} > /proc/sys/kernel/hostname 2>/dev/null \
        || true
    ''}

    ${lib.optionalString hasHomeManager ''
      ${runuser} -u ${username} -- ${coreutils}/bin/mkdir -p /home/${username}/.local/state/nix/profiles
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
    ''}

    # Provide the runtime dir a logind session (or lingering) would create, so
    # agent sockets land where tools expect them.
    mkdir -p /run/user/${toString uid}
    chown ${username}:users /run/user/${toString uid}
    chmod 700 /run/user/${toString uid}

    # `container run --ssh` forwards the host's SSH agent socket to
    # /var/host-services/ssh-auth.sock, created root:root by the runtime.
    if [ -S "''${SSH_AUTH_SOCK:-}" ]; then
      chown ${username}:users "$SSH_AUTH_SOCK"
    fi

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
    # session) inherits it and the shell gets job control. The `setsid -c`
    # branch is a safety net for a runtime that hands us a tty without
    # claiming it; unlike `runuser --pty` it adds no I/O proxy that an
    # activation orphan's death could wedge.
    # Non-interactive `container run <img> <cmd>` (no tty) just runs <cmd>.
    if [ -t 0 ] && ! (: >/dev/tty) 2>/dev/null; then
      exec ${pkgs.util-linux}/bin/setsid -c -w ${runuser} -u ${username} -- "$@"
    else
      exec ${runuser} -u ${username} -- "$@"
    fi
  '';

  # Apple `container image load` wants an OCI archive; regctl converts the
  # docker-archive in the Nix sandbox and the index `ref.name` is set so the
  # image loads under its name directly.
  mkOciArchive =
    {
      name,
      stream,
    }:
    pkgs.runCommand "${name}-oci.tar"
      {
        nativeBuildInputs = [
          pkgs.regclient
          pkgs.jq
          pkgs.gnutar
        ];
      }
      ''
        export TMPDIR="$PWD/tmp"
        mkdir -p "$TMPDIR" oci
        ${stream} > "$TMPDIR/image.tar"
        regctl image import "ocidir://$PWD/oci:latest" "$TMPDIR/image.tar"
        rm -f "$TMPDIR/image.tar"
        jq '.manifests[0].annotations["org.opencontainers.image.ref.name"] = "${name}:latest"' \
          oci/index.json > oci/index.json.new
        mv oci/index.json.new oci/index.json
        tar -cf "$out" -C oci .
      '';
in
{
  options.virtualisation.appleContainer = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "The (only) interactive user of the image; must exist in `users.users`.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 501;
      description = ''
        The *macOS* user's uid (501 for the first user). `container machine`
        opens its session as that uid and the shared /Users files carry it, so
        the NixOS user is pinned to it: `id -un` resolves, the exec picks
        HOME/SHELL from /etc/passwd, shared files are owned by the user.
      '';
    };

    imageName = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
      description = "OCI image name (loads as `<imageName>:latest`).";
    };

    shell = lib.mkOption {
      type = lib.types.package;
      default = declaredUserShell;
      defaultText = lib.literalExpression "users.users.<username>.shell as declared by the site config, or pkgs.bashInteractive";
      description = ''
        The real login shell sessions land in. Defaults to whatever the site
        config declares as `users.users.<username>.shell` (this module then
        force-replaces that option with a boot-wait wrapper — Apple opens
        machine sessions while NixOS is still booting — which execs this, as a
        login shell, from /run/current-system/sw/bin).
      '';
    };

    homeManagerMarker = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = ".config/fish/config.fish";
      description = ''
        $HOME-relative file the session wrapper additionally waits for —
        typically a home-manager-linked shell config, so the first machine
        session doesn't open before home-manager finishes. Sessions eat the
        wrapper's 60s timeout if it never appears.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default = cfg.imageName;
      defaultText = lib.literalExpression "config.virtualisation.appleContainer.imageName";
      description = ''
        Hostname applied under the `container run`, whose UTS namespace the
        runtime otherwise names after the container id.

        Use --name with `container machine`.

        Set to `""` to leave the container-id name untouched.
      '';
    };
  };

  config = {
    boot.isContainer = true;

    # See `binSh` above: /bin/sh gains a store-path PATH fallback so Apple's
    # empty-PATH `/sbin.machine/init` can resolve id/grep/cut and `--root`
    # sessions open. Must set the option, not just the image symlink: under
    # `container machine` envfs serves /bin/sh from a fallback-path derived from
    # `environment.binsh`.
    environment.binsh = lib.mkForce "${binSh}";

    networking = {
      # `container machine`'s bootstrap writes /etc/resolv.conf and /etc/hosts
      # before the guest boots; vminitd assigns the IP/route. So don't run DHCP
      # and don't let resolvconf replace /etc/resolv.conf afterwards.
      useDHCP = false;
      resolvconf.enable = lib.mkForce false;

      # Under `container machine`, Apple's /sbin.machine/init writes
      # /etc/hostname from the machine's `--name` (its CONTAINER_MACHINE_ID) on
      # every boot, right before exec'ing systemd — see apple/container
      # Sources/Plugins/MachineAPIServer/Resources/init. The write is
      # builtins-only (`echo > /etc/hostname`), so it succeeds even when the
      # init's command lookups are broken. Keeping networking.hostName empty
      # means NixOS manages no /etc/hostname of its own, so that runtime-written
      # file survives activation and systemd applies it: a machine created
      # `--name wasp` gets hostname `wasp`. A generation that *sets* hostName
      # instead clobbers Apple's file on every activation — and switching such a
      # machine back to "" deletes the managed file live, leaving the old name
      # as a transient hostname until the next boot rewrites /etc/hostname.
      hostName = lib.mkDefault "";
    };

    users = {
      allowNoPasswordLogin = true;

      # The image bakes a pre-activation /etc/passwd (see extraCommands below)
      # and relies on activation REPLACING it wholesale from the declaration —
      # which is `mutableUsers = false` semantics. The default (true) would
      # *merge* instead: existing entries keep their uid/shell, and password
      # state would be read back from the baked files.
      mutableUsers = lib.mkDefault false;

      # NixOS asserts `isNormalUser` ⇒ uid ≥ 1000, so take its prescribed escape
      # hatch (isSystemUser) and re-state what isNormalUser implied.
      users.${username} = {
        inherit uid;
        isNormalUser = lib.mkForce false;
        isSystemUser = true;
        group = "users";
        home = "/home/${username}";
        createHome = true;
        # The wait-for-boot wrapper: the machine session can fire inside
        # activation, after /etc/passwd is rewritten but before
        # /run/current-system or the home-manager files exist. Keeping the
        # wrapper as the *declared* shell closes that window for every session,
        # and pulls it into the image closure via the toplevel.
        shell = lib.mkForce "${machineSessionShell}";
        # No PAM session ⇒ logind never starts user@<uid>: without lingering
        # there is no user manager, no /run/user/<uid>, and no user services.
        linger = true;
      };

      # `container machine run --root` opens a root session that races first-boot
      # activation just like the interactive user's — root's default shell is the
      # activation-dependent /run/current-system/sw/bin/<shell>, which isn't there
      # yet ("…/fish: No such file or directory"). Give root the same boot-wait
      # wrapper (it has no home-manager, so it waits only for the system shell).
      users.root.shell = lib.mkForce "${rootSessionShell}";
    };

    # Make `specialfs` skip what the runtime already mounted and mount/tolerate
    # the rest, which is what systemd needs when the same image boots via
    # /sbin/init under `container machine`.
    system.activationScripts.specialfs = lib.mkForce ''
      specialMount() {
        local device="$1" mountPoint="$2" options="$3" fsType="$4"
        mountpoint -q "$mountPoint" && return 0
        mkdir -p "$mountPoint" && chmod 0755 "$mountPoint"
        mount -t "$fsType" -o "$options" "$device" "$mountPoint" 2>/dev/null || true
      }
      source ${config.system.build.earlyMountScript}
    '';

    system.build.containerImage = mkOciArchive {
      name = cfg.imageName;
      stream = pkgs.dockerTools.streamLayeredImage {
        name = cfg.imageName;
        tag = "latest";

        # `container machine` boots Apple's /sbin.machine/init — a `#!/bin/sh`
        # script virtiofs-mounted from the host bundle (apple/container
        # Sources/Plugins/MachineAPIServer/Resources/init).
        extraCommands = ''
          mkdir -p sbin tmp proc sys dev etc/machine run var home bin usr/bin
          # /sbin/init follows the rolling system profile (seeded below).
          # Apple's `container machine` re-execs /sbin/init on
          # every boot, so pointing it at the profile lets an in-place
          # `nixos-rebuild switch` inside the machine (whose /nix/store is its
          # own persistent volume) survive reboots — there's no bootloader here
          # to record the current generation, this symlink is that record.
          ln -sfn /nix/var/nix/profiles/system/init sbin/init
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
          cat > etc/passwd <<'EOF'
          root:x:0:0:root:/root:/bin/sh
          ${username}:x:${toString uid}:100::/home/${username}:${machineSessionShell}
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
          export NIX_REMOTE="local?root=$PWD" USER=nobody
          ${lib.getExe' pkgs.buildPackages.nix "nix-store"} --load-db < ${
            pkgs.closureInfo {
              rootPaths = [ toplevel ] ++ lib.optional hasHomeManager hmActivate;
            }
          }/registration
          ${lib.getExe pkgs.buildPackages.sqlite} nix/var/nix/db/db.sqlite \
            "UPDATE ValidPaths SET registrationTime = ''${SOURCE_DATE_EPOCH}"
          mkdir -p nix/var/nix/gcroots/docker
          ln -s ${toplevel} ${lib.optionalString hasHomeManager hmActivate} nix/var/nix/gcroots/docker/

          # Seed the system profile at generation 1 so the /sbin/init symlink
          # above resolves on first boot, and so `nix-env -p …/system --set`
          # (what `nixos-rebuild switch` runs) continues the generation chain
          # from here. `system` -> `system-1-link` mirrors nix's own layout: a
          # relative link to the numbered generation, which points at the store.
          # Profiles are GC roots themselves, so this also roots the toplevel.
          mkdir -p nix/var/nix/profiles
          ln -s ${toplevel} nix/var/nix/profiles/system-1-link
          ln -s system-1-link nix/var/nix/profiles/system
        '';

        config = {
          Entrypoint = [ "${entrypoint}" ];
          Cmd = [ "${machineSessionShell}" ];
          WorkingDir = "/home/${username}";
          Env = [ "TERM=xterm-256color" ];
        };
      };
    };
  };
}
