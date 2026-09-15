# Persistent, per-tmux-window lazygit popup.
#
# Run from a tmux `display-popup`. Rather than launching a throwaway lazygit
# that dies with the popup, this attaches to a detached, per-window tmux
# session that owns the lazygit process. The popup-only config (default.nix)
# maps `q` to `tmux detach-client`, which backgrounds that session, so the
# next summon reattaches with the same panel, selection and any open menu.
# `Q` (and C-c) still quit lazygit, which ends the session, so the following
# summon starts fresh.
#
# The session plumbing is the one lazyvim-popup uses; see there for why the
# origin window comes from $TMUX, why the session key is the window id, and
# why the attach needs `env -u TMUX` with an explicit socket.
origin="\$${TMUX##*,}"
window_id=$(tmux display-message -t "$origin" -p '#{window_id}')
start_dir=$(tmux display-message -t "$origin" -p '#{pane_current_path}')

session="_lazygit_${window_id#@}"

if ! tmux has-session -t "=${session}" 2>/dev/null; then
    # The pane gets the tmux server's environment, not this shell's, so the
    # popup config travels with the session. LAZYGIT_BIN and
    # LAZYGIT_POPUP_CONFIG come from the wrapper (default.nix).
    tmux new-session -d -s "${session}" -c "${start_dir}" \
        -e LG_CONFIG_FILE="$LAZYGIT_POPUP_CONFIG" "$LAZYGIT_BIN"
    tmux set-option -t "${session}" status off
    tmux set-option -t "${session}" prefix None
fi

exec env -u TMUX tmux -S "${TMUX%%,*}" attach-session -t "=${session}"
