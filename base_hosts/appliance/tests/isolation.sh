# Sourced by the Baguette probe and by the QEMU test driver as root.
test "$(stat -c %a /home/$user)" = 700
test ! -e /run/wrappers/bin/sudo
test ! -e /run/wrappers/bin/su
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
test "$(wc -l < /proc/swaps)" = 1
test "$(sysctl -n kernel.yama.ptrace_scope)" = 2
test "$(sysctl -n fs.suid_dumpable)" = 0
