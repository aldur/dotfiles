# Verify state without printing keys or message contents.
profile=/home/$user/.config/Signal
test -s "$profile/sql/db.sqlite"
# SQLCipher must have encrypted the database, and its key must be wrapped.
test "$(head -c 15 "$profile/sql/db.sqlite")" != 'SQLite format 3'
grep -Eq '"encryptedKey": *"[0-9a-f]+"' "$profile/config.json"
grep -Eq '"safeStorageBackend": *"gnome_libsecret"' "$profile/config.json"
if grep -Eq '"key" *:' "$profile/config.json"; then exit 1; fi
# Every Chromium renderer must retain seccomp and no_new_privs.
renderers=0
for proc in /proc/[0-9]*; do
  test -r "$proc/cmdline" || continue
  if tr '\0' ' ' < "$proc/cmdline" | grep -q -- '--type=renderer'; then
    grep -q '^NoNewPrivs:[[:space:]]*1$' "$proc/status"
    grep -q '^Seccomp:[[:space:]]*2$' "$proc/status"
    renderers=$((renderers + 1))
  fi
done
test "$renderers" -gt 0
