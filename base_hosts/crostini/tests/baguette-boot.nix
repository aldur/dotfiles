# The boot check of the Baguette image, with the probes of this guest on
# top of the shared smoke harness.
{
  pkgs,
  runCommand,
  writeText,
  xz,
  zstd,
  configuration,
  crostini,
}:
let
  persistentHome = configuration.extendModules {
    modules = [ { crostini.impermanence.enable = pkgs.lib.mkForce false; } ];
  };
  # The root login of the rebuild probe. The image trusts other keys; the
  # probe binds this one over them for the boot.
  keys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
  inherit (configuration.config) mainUser;
  kernel = configuration.config.boot.kernelPackages.kernel;

  # A module of the test kernel, uncompressed. The guest must refuse to
  # load it: crostini.nix sets kernel.modules_disabled.
  module =
    runCommand "dummy.ko"
      {
        nativeBuildInputs = [
          xz
          zstd
        ];
      }
      ''
        src=$(echo ${kernel.modules}/lib/modules/${kernel.modDirVersion}/kernel/drivers/net/dummy.ko*)
        case "$src" in
          *.xz) xz -dc "$src" > $out ;;
          *.zst) zstd -dc "$src" > $out ;;
          *) cp "$src" $out ;;
        esac
      '';
in
# Changing home persistence must not disable ChromeOS registration.
assert persistentHome.config.users.users.${persistentHome.config.mainUser}.linger == true;
crostini.lib.mkBaguetteSmokeTest {
  inherit configuration;
  user = mainUser;
  name = "crostini-baguette-smoke";
  probeFiles = {
    inherit module;
    ssh-key = keys.snakeOilEd25519PrivateKey;
    authorized-keys = writeText "authorized_keys" "${keys.snakeOilEd25519PublicKey}\n";
  };
  extraProbe = ''
    # Capture output only after checking the command's status. An echo with
    # command substitution would discard that status.
    expect_success() {
      if probe_output=$("$@" 2>&1); then
        return 0
      fi
      printf 'FAIL: %s\n%s\n' "$*" "$probe_output" >&2
      return 1
    }
    expect_failure() {
      if probe_output=$("$@" 2>&1); then
        printf 'FAIL: command unexpectedly succeeded: %s\n%s\n' "$*" "$probe_output" >&2
        return 1
      fi
    }

    expect_success findmnt -n -o FSTYPE /home
    echo "PROBE home-fs $probe_output"
    expect_success systemctl is-active systemd-sysctl.service
    sysctl_state=$probe_output
    modules_disabled=absent
    if [ -e /proc/sys/kernel/modules_disabled ]; then
      expect_success sysctl -n kernel.modules_disabled
      modules_disabled=$probe_output
    fi
    echo "PROBE sysctl $sysctl_state modules_disabled=$modules_disabled"
    expect_failure insmod "$probe/module"
    echo "PROBE insmod $probe_output"
    for target in / /home /nix/store /home/$user/Work /home/$user/.claude /home/$user/.codex /dev/shm /var/tmp; do
      expect_success findmnt -n -o OPTIONS "$target"
      echo "PROBE mount $target $probe_output"
    done
    expect_success stat -c %a "/home/$user/.codex"
    echo "PROBE codex-mode $probe_output"

    # nosuid and nodev on the root, the home tmpfs and a bind from
    # /persist. Root plants a setuid copy of id and a device node in each.
    # The user must get its own uid and no device. The controls are the
    # mounts made for such files: /run/wrappers/bin for setuid, /dev for
    # device nodes. There the same files work.
    in_session mkdir -p "/home/$user/Work/probe"
    for dir in /home/$user /home/$user/Work /var/tmp /run/wrappers/bin; do
      # id is the coreutils multicall binary. The copy needs the program name.
      cp -L /run/current-system/sw/bin/id "$dir/probe-id"
      chown root:root "$dir/probe-id"
      chmod 4755 "$dir/probe-id"
      if [ "$dir" = /var/tmp ]; then
        expect_failure in_session "$dir/probe-id" --coreutils-prog=id -u
      else
        expect_success in_session "$dir/probe-id" --coreutils-prog=id -u
      fi
      echo "PROBE setuid $dir uid=$probe_output"
    done
    for dir in /home/$user /home/$user/Work /var/tmp /dev; do
      mknod -m 666 "$dir/probe-null" c 1 3
      if [ "$dir" = /dev ]; then
        expect_success in_session cat "$dir/probe-null"
        echo "PROBE nodev $dir readable"
      else
        expect_failure in_session cat "$dir/probe-null"
        echo "PROBE nodev $dir $probe_output"
      fi
    done

    # noexec on shared memory and /var/tmp. The home keeps exec: see the
    # exec probe below.
    for dir in /dev/shm /var/tmp; do
      in_session sh -c "printf '#!/bin/sh\necho ran\n' > $dir/probe.sh && chmod +x $dir/probe.sh"
      expect_failure in_session "$dir/probe.sh"
      echo "PROBE noexec $dir $probe_output"
    done

    # Commands inherit the booted user manager's PAM environment and umask.
    # Check both shells and the manager; never inherit the root probe's umask.
    expect_success in_session bash -lc umask
    echo "PROBE umask login $probe_output"
    expect_success in_session fish -c umask
    echo "PROBE umask fish $probe_output"
    manager_pid=$(systemctl show -p MainPID --value user@1000.service)
    expect_success grep Umask "/proc/$manager_pid/status"
    echo "PROBE umask manager $(printf '%s\n' "$probe_output" | tr -s '[:space:]' ' ')"

    # What must keep working: a script in the home, the one sudo rule of
    # the guest, the agent sandbox from a workspace under a bind, and a
    # build through the daemon.
    expect_success in_session sh -c 'printf "#!/bin/sh\necho from-home\n" > ~/probe.sh && chmod +x ~/probe.sh && ~/probe.sh'
    echo "PROBE exec $probe_output"
    expect_success in_session /run/wrappers/bin/sudo -n systemctl restart pcscd.service
    echo "PROBE sudo ok"
    expect_success in_session sh -c 'cd ~/Work/probe && /etc/profiles/per-user/'"$user"'/bin/agent-sandbox -- echo ok'
    echo "PROBE sandbox $(printf '%s\n' "$probe_output" | tail -n 1)"
    # $out belongs to the Nix builder, not this probe's shell.
    # shellcheck disable=SC2016
    expect_success in_session nix build --offline --no-link --print-out-paths --impure --expr 'derivation { name = "probe"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ok > $out" ]; }'
    echo "PROBE nix $(printf '%s\n' "$probe_output" | tail -n 1)"

    # The root login of the guest, and what it administers with.
    install -m 0600 "$probe/ssh-key" /root/probe-key
    # The entry of /etc is a symlink into the read-only store, so a bind
    # mount would target the store. Replace the link for this boot.
    keys=/etc/ssh/authorized_keys.d/root
    rm -f $keys
    install -m 0444 -o root -g root "$probe/authorized-keys" "$keys"
    expect_success stat -c '%U %a %s' "$keys"
    echo "PROBE sshkeys $probe_output"

    # ssh talks to the terminal even with a redirected stdin, and this
    # stdout is the serial port. Every ssh runs with the port closed and
    # its output in a file; the probe prints the file afterwards.
    ssh_opts=(-n -T -o BatchMode=yes -o LogLevel=ERROR -i /root/probe-key
      -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null)
    ssh_root() {
      # The caller supplies the intended remote command string.
      # shellcheck disable=SC2029
      ssh "''${ssh_opts[@]}" root@127.0.0.1 "$@" > /tmp/ssh.out 2>&1 < /dev/null
    }

    ssh_root umask
    echo "PROBE ssh umask $(tr -d '\r' < /tmp/ssh.out | tail -n 1)"

    # A rebuild over SSH, as root administers the guest. The switch is to
    # the running system, so only the activation and the profile change.
    system=$(readlink -f /run/current-system)
    if ssh_root "nix-env -p /nix/var/nix/profiles/system --set $system && $system/bin/switch-to-configuration switch"; then
      expect_success readlink /nix/var/nix/profiles/system
      echo "PROBE rebuild ok $probe_output"
    else
      cat /tmp/ssh.out >&2
      exit 1
    fi
    # The daemon serves the two users of the guest, not everyone.
    expect_success grep '^allowed-users' /etc/nix/nix.conf
    echo "PROBE nix users $(printf '%s\n' "$probe_output" | tr -s ' ')"

    # A root session over the loopback needs no tunnel and no agent. The
    # daemon sets up a remote forward when the session opens, so it
    # refuses this one there; ExitOnForwardFailure turns that into a
    # failure of ssh itself.
    if ssh "''${ssh_opts[@]}" -o ExitOnForwardFailure=yes -R 12222:127.0.0.1:22 \
      root@127.0.0.1 true > /tmp/ssh-forward.out 2>&1; then
      echo "FAIL: SSH allowed remote TCP forwarding" >&2
      exit 1
    fi
    cat /tmp/ssh-forward.out
    grep -Fq 'remote port forwarding failed for listen port 12222' /tmp/ssh-forward.out
    echo "PROBE sshd tcpforward refused"
    # The effective values of the daemon, defaults included. The image
    # sets no AllowAgentForwarding, so the default of OpenSSH applies.
    # The case of the keys in the output changes between versions.
    sshd -T > /tmp/sshd-T.out 2>&1 || { cat /tmp/sshd-T.out; exit 1; }
    for directive in AllowTcpForwarding AllowAgentForwarding X11Forwarding; do
      probe_output=$(awk -v key="$directive" 'tolower($1) == tolower(key) { print $2 }' /tmp/sshd-T.out)
      echo "PROBE sshd $directive $probe_output"
    done

    # What the activation writes must keep its modes, and the guest must
    # still work after it.
    expect_success stat -c '%n=%a' /etc/passwd /etc/group /etc/shadow /run/wrappers/bin/sudo
    echo "PROBE modes $(printf '%s\n' "$probe_output" | tr '\n' ' ')"
    expect_success systemctl list-units --state=failed --no-legend --plain
    echo "PROBE after-rebuild failed [$(printf '%s' "$probe_output" | awk '{print $1}' | tr '\n' ' ')]"
    expect_success in_session /run/wrappers/bin/sudo -n systemctl restart pcscd.service
    echo "PROBE after-rebuild sudo ok"
  '';
  extraChecks = [
    # The representative Termina kernel has no module support.
    "sysctl active modules_disabled=absent"
    "insmod .*Function not implemented"
    "home-fs tmpfs$"
    "home ${mainUser} 700$"
    "mount / .*nosuid.*nodev"
    "mount /home .*nosuid.*nodev"
    "mount /home/${mainUser}/Work .*nosuid.*nodev"
    "mount /home/${mainUser}/.claude .*nosuid.*nodev"
    "mount /home/${mainUser}/.codex .*nosuid.*nodev"
    "codex-mode 700$"
    "mount /dev/shm .*noexec"
    "mount /var/tmp .*noexec"
    "setuid /home/${mainUser} uid=1000$"
    "setuid /home/${mainUser}/Work uid=1000$"
    # noexec refuses the setuid copy before nosuid gets a say.
    "setuid /var/tmp uid=.*Permission denied"
    "setuid /run/wrappers/bin uid=0$"
    "nodev /home/${mainUser} cat: .*Permission denied"
    "nodev /home/${mainUser}/Work cat: .*Permission denied"
    "nodev /var/tmp cat: .*Permission denied"
    "nodev /dev readable"
    "noexec /dev/shm .*Permission denied"
    "noexec /var/tmp .*Permission denied"
    "umask login 0077$"
    "umask fish 0077$"
    "umask manager Umask: 0077 $"
    "exec from-home"
    "sshkeys root 444 [0-9]"
    "ssh umask 0077$"
    "rebuild ok system-[0-9]*-link$"
    "modes /etc/passwd=644 /etc/group=644 /etc/shadow=640 /run/wrappers/bin/sudo=4510"
    "after-rebuild failed \\[ *\\]"
    "after-rebuild sudo ok"
    "nix users allowed-users = root ${mainUser}$"
    "sshd tcpforward refused$"
    "sshd AllowTcpForwarding no$"
    "sshd AllowAgentForwarding yes$"
    "sshd X11Forwarding no$"
    "sudo ok"
    "sandbox ok"
    "nix /nix/store/.*-probe$"
  ];
}
