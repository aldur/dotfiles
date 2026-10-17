# @flag --check Check the keyring without opening a prompt.
declare argc_check
eval "$(argc --argc-eval "$0" "$@")"

umask 077
unset NODE_OPTIONS NODE_PATH ELECTRON_RUN_AS_NODE ELECTRON_ENABLE_LOGGING SIGNAL_PASSWORD_STORE
keyring="$HOME/.local/share/keyrings/login.keyring"

fail() { printf 'Signal keyring: %s\n' "$*" >&2; exit 1; }
ready() {
  # gdbus introspects first. GNOME Keyring can crash on a new client's property read.
  gdbus call --session --dest org.freedesktop.secrets \
    --object-path /org/freedesktop/secrets/aliases/default \
    --method org.freedesktop.DBus.Properties.Get org.freedesktop.Secret.Collection Locked \
    2>/dev/null | grep -qx '(<false>,)'
}
encrypted() {
  head -c 16 "$keyring" 2>/dev/null | cmp -s - <(printf 'GnomeKeyring\n\r\0\n')
}
prompt() {
  yad --entry --hide-text --title="$1" --text="$1" \
    --entry-label=Password --button=yad-cancel:1 --button=yad-ok:0
}

if ! ready; then
  if [[ ${argc_check:-0} == 1 ]]; then fail 'Keyring is locked'; fi
  existing=false
  if [[ -f "$keyring" ]]; then existing=true; fi
  if ! password=$(prompt 'Unlock Signal keyring') || [[ -z "$password" ]]; then
    fail 'A nonempty keyring password is required'
  fi
  if ! "$existing"; then
    if ! confirmation=$(prompt 'Confirm Signal keyring password') || [[ -z "$confirmation" ]]; then
      fail 'A nonempty keyring password is required'
    fi
    if [[ "$password" != "$confirmation" ]]; then fail 'The passwords do not match'; fi
    unset confirmation
  fi
  printf '%s' "$password" | gnome-keyring-daemon --replace --unlock --components=secrets >/dev/null
  unset password
  for ((attempt=0; attempt<50; attempt++)); do
    if ready; then break; fi
    sleep 0.1
  done
  if ! ready; then
    if "$existing"; then fail 'Incorrect keyring password; Signal was not started'; fi
    fail 'Could not unlock the new keyring; Signal was not started'
  fi
fi
# Secret Service reports blank-password keyrings as unlocked, but they are plaintext.
if ! encrypted; then fail 'Signal requires an encrypted login keyring'; fi
if [[ ${argc_check:-0} == 1 ]]; then exit 0; fi
