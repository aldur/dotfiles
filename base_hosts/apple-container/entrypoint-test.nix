# Runs the real OCI entrypoint and forces one stage at a time to fail. A user
# namespace plus a chroot stands in for the container. Fakes replace only the
# nix daemon, nix-store, the two activation scripts, runuser, and chown; the
# entrypoint script itself is the built one. The success path must reach the
# shell hand-off, and every failed stage must exit before it.
{ nixos }:
let
  pkgs = nixos.pkgs;
  inherit (pkgs) lib;
  inherit (nixos.config.system.build) containerEntrypoint toplevel;
  inherit (nixos.config.virtualisation.appleContainer) username;
  hmActivate = nixos.config.home-manager.users.${username}.home.activationPackage;
  nix = nixos.config.nix.package;
  inherit (pkgs) coreutils util-linux;
  bash = "${pkgs.bash}/bin/bash";

  fakeDaemon = pkgs.writeShellScript "fake-nix-daemon" ''
    if [ "''${FAIL_STAGE:-}" = daemon ]; then
      echo "fake nix-daemon: refusing to start"
      exit 1
    fi
    exec ${pkgs.python3}/bin/python3 -c '
    import socket, time
    s = socket.socket(socket.AF_UNIX)
    s.bind("/nix/var/nix/daemon-socket/socket")
    s.listen(1)
    time.sleep(3600)
    '
  '';
  fakeNixStore = pkgs.writeShellScript "fake-nix-store" ''
    if [ "''${FAIL_STAGE:-}" = preflight ]; then
      echo "fake nix-store: cannot connect to daemon"
      exit 1
    fi
    echo "fake nix-store: ok"
  '';
  fakeSystemActivate = pkgs.writeShellScript "fake-system-activate" ''
    if [ "''${FAIL_STAGE:-}" = system ]; then
      echo "fake system activation: boom"
      exit 1
    fi
    echo "fake system activation: ok"
    mkdir -p /home/${username}
  '';
  fakeHmActivate = pkgs.writeShellScript "fake-home-manager-activate" ''
    if [ "''${FAIL_STAGE:-}" = home-manager ]; then
      echo "fake home-manager activation: boom"
      exit 1
    fi
    echo "fake home-manager activation: ok"
  '';
  # runuser -u <user> -- <cmd...>: drop the privilege switch, keep the command.
  fakeRunuser = pkgs.writeShellScript "fake-runuser" ''
    shift 3
    if [ "''${FAIL_STAGE:-}" = hm-mkdir ] && [ "$1" = ${coreutils}/bin/mkdir ]; then
      echo "fake runuser: mkdir refused" >&2
      exit 1
    fi
    exec "$@"
  '';
  # chown cannot target an unmapped uid inside the namespace; the fake also
  # stands in for any command without an explicit `|| fail` branch.
  fakeChown = pkgs.writeShellScript "fake-chown" ''
    if [ "''${FAIL_STAGE:-}" = unexpected ]; then
      echo "fake chown: refused" >&2
      exit 1
    fi
  '';

  # stage | banner the entrypoint must print | log line it must echo back
  cases = [
    [
      "daemon"
      "nix-daemon socket missing"
      "fake nix-daemon: refusing to start"
    ]
    [
      "system"
      "system activation failed"
      "fake system activation: boom"
    ]
    [
      "hm-mkdir"
      "command failed at line"
      "fake runuser: mkdir refused"
    ]
    [
      "preflight"
      "nix daemon preflight failed"
      "fake nix-store: cannot connect to daemon"
    ]
    [
      "home-manager"
      "home-manager activation failed"
      "fake home-manager activation: boom"
    ]
    [
      "unexpected"
      "command failed at line"
      "fake chown: refused"
    ]
  ];
  caseLines = lib.concatMapStringsSep "\n" (lib.concatStringsSep "\t") cases;
in
pkgs.runCommand "apple-container-entrypoint-test"
  {
    nativeBuildInputs = [ util-linux ];
  }
  ''
    root=$TMPDIR/root
    mkdir -p "$root"/{nix/store,nix/var/nix,proc,dev,tmp,var/log,run,home}
    : > "$root/dev/null"

    # coreutils and nix are multi-call binaries behind symlinks, so a bind
    # over one name would replace every command. Overlay whole bin dirs.
    fakes=$TMPDIR/fakes
    mkdir -p "$fakes/cu-bin" "$fakes/nix-bin"
    cp ${coreutils}/bin/coreutils "$fakes/cu-bin/coreutils"
    for f in ${coreutils}/bin/*; do
      n=''${f##*/}
      case $n in
        coreutils | chown) ;;
        *) ln -s coreutils "$fakes/cu-bin/$n" ;;
      esac
    done
    cp ${fakeChown} "$fakes/cu-bin/chown"
    cp ${fakeDaemon} "$fakes/nix-bin/nix-daemon"
    cp ${fakeNixStore} "$fakes/nix-bin/nix-store"

    cat > "$TMPDIR/cases" <<'CASES'
    ${caseLines}
    CASES

    export root fakes
    unshare -Urm --propagation private ${bash} -e -u -c '
      # The sandbox binds each store path separately; the locked child mounts
      # only come along with a recursive bind.
      mount --rbind /nix/store "$root/nix/store"
      mount --bind /dev/null "$root/dev/null"
      mount --bind "$fakes/cu-bin" "$root${coreutils}/bin"
      mount --bind "$fakes/nix-bin" "$root${nix}/bin"
      mount --bind ${fakeSystemActivate} "$root${toplevel}/activate"
      mount --bind ${fakeHmActivate} "$root${hmActivate}/activate"
      mount --bind ${fakeRunuser} "$root${util-linux}/bin/runuser"

      # Each stage gets a fresh pid namespace, so the fake daemon dies with
      # it, and a fresh daemon socket dir, so no stale socket satisfies the
      # wait loop.
      run_stage() {
        rm -rf "$root/nix/var/nix/daemon-socket"
        FAIL_STAGE=$1 unshare -pf --mount-proc --root="$root" \
          ${containerEntrypoint} ${bash} -c "echo REACHED_SHELL" \
          > "$TMPDIR/$1.out" 2>&1 && rc=0 || rc=$?
        echo "== stage $1: exit $rc"
        cat "$TMPDIR/$1.out"
      }
      expect() {
        case $(cat "$TMPDIR/$1.out") in
          *"$2"*) ;;
          *) echo "stage $1: expected output to contain: $2" >&2; exit 1 ;;
        esac
      }
      reject() {
        case $(cat "$TMPDIR/$1.out") in
          *"$2"*) echo "stage $1: output must not contain: $2" >&2; exit 1 ;;
        esac
      }

      run_stage ok
      [ "$rc" = 0 ] || { echo "stage ok: exit $rc" >&2; exit 1; }
      expect ok REACHED_SHELL
      reject ok "entrypoint:"

      while IFS=$(printf "\t") read -r stage banner logline; do
        run_stage "$stage"
        [ "$rc" != 0 ] || { echo "stage $stage: reached exit 0" >&2; exit 1; }
        reject "$stage" REACHED_SHELL
        expect "$stage" "$banner"
        expect "$stage" "$logline"
      done < "$TMPDIR/cases"
    '
    touch "$out"
  ''
