{ configuration, crostini }:
crostini.lib.mkBaguetteSmokeTest {
  inherit configuration;
  name = "browser-baguette-smoke";
  extraProbe = ''
    # The real profile must land on the image's writable disk, not tmpfs.
    test "$(findmnt -n -o FSTYPE -T /home/$user)" = btrfs
    test "$(stat -c %a /home/$user)" = 700
    test "$(in_session sh -c umask)" = 0077
    test ! -e /run/wrappers/bin/sudo
    test ! -e /run/wrappers/bin/su
    for disk in /dev/vda /dev/vdb; do
      test "$(stat -c '%U:%G:%a' "$disk")" = root:root:600
      as_user test ! -r "$disk"
    done
    systemctl is-active firewall.service
    systemctl is-active systemd-sysctl.service
    echo "PROBE browser isolation ok"

    # Run the shipped browser as the ordinary session user. This catches
    # sandbox/graphics regressions from hardening without a network login.
    in_session --property=RuntimeMaxSec=180 firefox --headless \
      --screenshot /home/$user/browser.png about:blank \
      > /tmp/firefox.log 2>&1 || { cat /tmp/firefox.log; exit 1; }
    test -s /home/$user/browser.png
    in_session xdg-mime query default x-scheme-handler/https | grep -Fx firefox.desktop
    echo "PROBE browser rendered"
  '';
  extraChecks = [
    "browser isolation ok$"
    "browser rendered$"
  ];
}
