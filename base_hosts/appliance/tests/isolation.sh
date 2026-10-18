# Sourced by the Baguette probe and by the QEMU test driver as root.
test "$(stat -c %a /home/$user)" = 700
for wrapper in sudo su; do test ! -e "/run/wrappers/bin/$wrapper"; done
wrappers=$(find /run/wrappers -type f -perm /6000)
test -z "$wrappers"
test -z "$(getcap -r /run/wrappers)"
for unit in serial-getty@.service getty@.service container-getty@.service; do
  getty=$(systemctl cat "$unit")
  if grep -- --autologin <<< "$getty"; then exit 1; fi
done
for unit in logrotate.timer systemd-oomd.service nscd.service systemd-timesyncd.service; do
  if systemctl is-active --quiet "$unit"; then exit 1; fi
done
if systemctl is-active --quiet sshd.service; then exit 1; fi
test ! -S /nix/var/nix/daemon-socket/socket
if systemctl is-active --quiet nix-daemon.service nix-daemon.socket; then exit 1; fi
for unit in firewall systemd-sysctl; do
  systemctl is-active --quiet "$unit.service"
done
for directory in /tmp /var/tmp /var/log; do
  test "$(findmnt -n -o FSTYPE -T "$directory")" = tmpfs
done
findmnt -n -o OPTIONS / | grep -w nosuid | grep -w nodev
findmnt -n -o OPTIONS /state | grep -w rw
root_type=$(findmnt -n -o FSTYPE /)
case "$root_type" in overlay|tmpfs) ;; *) exit 1 ;; esac
echo "PROBE isolation root $root_type"
test "$(wc -l < /proc/swaps)" = 1
test "$(sysctl -n kernel.yama.ptrace_scope)" = 2
test "$(sysctl -n fs.suid_dumpable)" = 0
