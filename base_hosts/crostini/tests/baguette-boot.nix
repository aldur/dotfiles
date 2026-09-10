# The boot check of the Baguette image, with the probes of this guest on
# top of nixos-crostini.lib.mkBaguetteSmokeTest.
{
  lib,
  pkgs,
  runCommand,
  writeText,
  xz,
  zstd,
  mkBaguetteSmokeTest,
  configuration,
  # The termina kernel from nixos-crostini. It has no module support, so
  # the module probe expects a different refusal.
  terminaKernel ? null,
}:
let
  termina = terminaKernel != null;
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
mkBaguetteSmokeTest {
  inherit configuration;
  user = mainUser;
  name = "crostini-baguette-boot" + lib.optionalString termina "-termina";
  kernel = if termina then "${terminaKernel}/kernel" else null;
  kernelRelease = if termina then "${terminaKernel}/release" else null;
  probeFiles = {
    inherit module;
    ssh-key = keys.snakeOilEd25519PrivateKey;
    authorized-keys = writeText "authorized_keys" "${keys.snakeOilEd25519PublicKey}\n";
  };
  extraProbe = ''
    echo "PROBE home-fs $(findmnt -n -o FSTYPE /home)"
    echo "PROBE sysctl $(systemctl is-active systemd-sysctl.service) modules_disabled=$(sysctl -n kernel.modules_disabled 2>/dev/null || echo absent)"
    echo "PROBE lockdown $(cat /sys/kernel/security/lockdown 2>/dev/null || echo absent)"
    echo "PROBE insmod $(insmod $probe/module 2>&1 || true)"
    for target in / /home /nix/store /home/$user/Work /home/$user/.claude /dev/shm /var/tmp; do
      echo "PROBE mount $target $(findmnt -n -o OPTIONS $target)"
    done

    # nosuid and nodev on the root, the home tmpfs and a bind from
    # /persist. Root plants a setuid copy of id and a device node in each.
    # The user must get its own uid and no device. The controls are the
    # mounts made for such files: /run/wrappers/bin for setuid, /dev for
    # device nodes. There the same files work.
    as_user mkdir -p /home/$user/Work/probe
    for dir in /home/$user /home/$user/Work /var/tmp /run/wrappers/bin /dev; do
      # id is the coreutils multicall binary. The copy needs the program name.
      cp -L /run/current-system/sw/bin/id $dir/probe-id
      chown root:root $dir/probe-id
      chmod 4755 $dir/probe-id
      mknod -m 666 $dir/probe-null c 1 3
      echo "PROBE setuid $dir uid=$(as_user $dir/probe-id --coreutils-prog=id -u 2>&1)"
      echo "PROBE nodev $dir $(as_user cat $dir/probe-null 2>&1 && echo readable)"
    done

    # noexec on shared memory and /var/tmp. The home keeps exec: see the
    # exec probe below.
    for dir in /dev/shm /var/tmp; do
      as_user sh -c "printf '#!/bin/sh\necho ran\n' > $dir/probe.sh && chmod +x $dir/probe.sh"
      echo "PROBE noexec $dir $(as_user $dir/probe.sh 2>&1)"
    done

    # umask 077 through PAM and through the shell init, for a login shell,
    # for fish, and for the user manager that starts the user services.
    echo "PROBE umask login $(as_user bash -lc umask)"
    echo "PROBE umask fish $(as_user fish -c umask)"
    echo "PROBE umask manager $(grep Umask /proc/$(systemctl show -p MainPID --value user@1000.service)/status | tr -s '[:space:]' ' ')"

    # What must keep working: a script in the home, the one sudo rule of
    # the guest, the agent sandbox from a workspace under a bind, and a
    # build through the daemon.
    echo "PROBE exec $(as_user sh -c 'printf "#!/bin/sh\necho from-home\n" > ~/probe.sh && chmod +x ~/probe.sh && ~/probe.sh' 2>&1)"
    echo "PROBE sudo $(as_user /run/wrappers/bin/sudo -n systemctl restart pcscd.service 2>&1 && echo ok)"
    echo "PROBE sandbox $(as_user sh -c 'cd ~/Work/probe && /etc/profiles/per-user/'$user'/bin/agent-sandbox -- echo ok' 2>&1 | tail -n 1)"
    echo "PROBE nix $(as_user nix build --offline --no-link --print-out-paths --impure --expr 'derivation { name = "probe"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo ok > $out" ]; }' 2>&1 | tail -n 1)"

    # The root login of the guest, and what it administers with.
    install -m 0600 $probe/ssh-key /root/probe-key
    # The entry of /etc is a symlink into the read-only store, so a bind
    # mount would target the store. Replace the link for this boot.
    keys=/etc/ssh/authorized_keys.d/root
    rm -f $keys
    install -m 0444 -o root -g root $probe/authorized-keys $keys
    echo "PROBE sshkeys $(stat -c '%U %a %s' $keys 2>&1)"

    # ssh talks to the terminal even with a redirected stdin, and this
    # stdout is the serial port. Every ssh runs with the port closed and
    # its output in a file; the probe prints the file afterwards.
    ssh_opts="-n -T -o BatchMode=yes -o LogLevel=ERROR -i /root/probe-key
      -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null"
    ssh_root() {
      ssh $ssh_opts root@127.0.0.1 "$@" > /tmp/ssh.out 2>&1 < /dev/null
    }

    ssh_root umask
    echo "PROBE ssh umask $(tr -d '\r' < /tmp/ssh.out | tail -n 1)"

    # A rebuild over SSH, as root administers the guest. The switch is to
    # the running system, so only the activation and the profile change.
    system=$(readlink -f /run/current-system)
    if ssh_root "nix-env -p /nix/var/nix/profiles/system --set $system && $system/bin/switch-to-configuration switch"; then
      echo "PROBE rebuild ok $(readlink /nix/var/nix/profiles/system)"
    else
      echo "PROBE rebuild failed: $(tr -d '\r' < /tmp/ssh.out | tail -n 3 | tr '\n' ' ')"
    fi
    # The daemon serves the two users of the guest, not everyone.
    echo "PROBE nix users $(grep '^allowed-users' /etc/nix/nix.conf | tr -s ' ')"

    # A root session over the loopback needs no tunnel and no agent. The
    # daemon sets up a remote forward when the session opens, so it
    # refuses this one there; ExitOnForwardFailure turns that into a
    # failure of ssh itself.
    if ssh $ssh_opts -o ExitOnForwardFailure=yes -R 12222:127.0.0.1:22 \
      root@127.0.0.1 true > /tmp/ssh-forward.out 2>&1; then
      echo "PROBE sshd tcpforward allowed"
    else
      echo "PROBE sshd tcpforward refused"
    fi
    for directive in AllowTcpForwarding AllowAgentForwarding X11Forwarding; do
      echo "PROBE sshd $directive $(grep -i "^$directive " /etc/ssh/sshd_config | awk '{print $2}')"
    done

    # What the activation writes must keep its modes, and the guest must
    # still work after it.
    echo "PROBE modes $(stat -c '%n=%a' /etc/passwd /etc/group /etc/shadow /run/wrappers/bin/sudo | tr '\n' ' ')"
    echo "PROBE after-rebuild failed [$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')]"
    echo "PROBE after-rebuild sudo $(as_user /run/wrappers/bin/sudo -n systemctl restart pcscd.service 2>&1 && echo ok)"
  '';
  extraChecks =
    (
      if termina then
        [
          # The termina kernel has no module support. systemd-sysctl must
          # stay active with the sysctl absent.
          "sysctl active modules_disabled=absent"
          "insmod .*Function not implemented"
        ]
      else
        [
          # EPERM with no lockdown and the sysctl at 1 comes from
          # modules_disabled alone.
          "sysctl active modules_disabled=1"
          "lockdown (absent|\\[none\\])"
          "insmod .*Operation not permitted"
        ]
    )
    ++ [
      "home-fs tmpfs$"
      "home ${mainUser} 700$"
      "mount / .*nosuid.*nodev"
      "mount /home .*nosuid.*nodev"
      "mount /home/${mainUser}/Work .*nosuid.*nodev"
      "mount /home/${mainUser}/.claude .*nosuid.*nodev"
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
      "sshd AllowAgentForwarding no$"
      "sshd X11Forwarding no$"
      "sudo ok"
      "sandbox ok"
      "nix /nix/store/.*-probe$"
    ];
}
