test "$(findmnt -n -o FSTYPE -T /home/$user)" = overlay
test "$(findmnt -n -o FSTYPE /state)" = btrfs
# ChromeOS's Sommelier uses this path with native Wayland clients too.
test -r /usr/share/X11/xkb/rules/evdev
test -r /usr/share/X11/xkb/symbols/us
test "$(in_session sh -c umask)" = 0077
for disk in /dev/vda /dev/vdb; do
  test "$(stat -c '%U:%G:%a' "$disk")" = root:root:600
  as_user test ! -r "$disk"
done
