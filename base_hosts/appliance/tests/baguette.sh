test "$(findmnt -n -o FSTYPE -T /home/$user)" = btrfs
test "$(in_session sh -c umask)" = 0077
for disk in /dev/vda /dev/vdb; do
  test "$(stat -c '%U:%G:%a' "$disk")" = root:root:600
  as_user test ! -r "$disk"
done
