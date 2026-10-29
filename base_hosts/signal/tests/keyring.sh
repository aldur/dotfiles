# Run against a separate home and bus so the test cannot change the live keyring.
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
mkdir -m 700 "$workspace/home" "$workspace/run"
HOME="$workspace/home" XDG_DATA_HOME="$workspace/home/.local/share" XDG_RUNTIME_DIR="$workspace/run" \
  dbus-run-session -- bash -euo pipefail -c '
    # EOF means no password; a NUL byte supplies an empty C string.
    printf "\0" | gnome-keyring-daemon --foreground --unlock --components=secrets &
    daemon=$!
    trap "kill $daemon 2>/dev/null || true; wait $daemon 2>/dev/null || true" EXIT
    for ((attempt=0; attempt<50; attempt++)); do
      if busctl --user --auto-start=no call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service ReadAlias s default 2>/dev/null | grep -q /collection/login; then break; fi
      sleep 0.1
    done
    busctl --user --auto-start=no call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service ReadAlias s default | grep -q /collection/login
    for option in --check ""; do
      if error=$(signal-desktop $option 2>&1); then exit 1; fi
      if ! grep -F "Signal requires an encrypted login keyring" <<< "$error"; then
        printf "Unexpected Signal error: %s\n" "$error" >&2
        exit 1
      fi
    done
    test ! -e "$HOME/.config/Signal/sql/db.sqlite"
  '
