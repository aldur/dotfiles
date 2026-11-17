# Persistent, per-tmux-window popup.
#
# Usage: tmux-popup-session NAME COMMAND [ARG...]
#
# Run from a tmux `display-popup`. Rather than launching a throwaway COMMAND
# that dies with the popup, this attaches to a detached, per-window tmux
# session that owns the COMMAND process. COMMAND hides the popup with
# `passthru.hide` (default.nix), which detaches the popup client and
# keeps the session, so the next summon reattaches with the same state. When
# COMMAND exits, the session ends, so the following summon starts fresh.
#
# The session plumbing is the one lazyvim-popup uses; see there for why the
# origin window comes from $TMUX, why the session key is the window id, and
# why the attach needs `env -u TMUX` with an explicit socket.
name=$1
shift

origin="\$${TMUX##*,}"
window_id=$(tmux display-message -t "$origin" -p '#{window_id}')
start_dir=$(tmux display-message -t "$origin" -p '#{pane_current_path}')

session="_${name}_${window_id#@}"

if ! tmux has-session -t "=${session}" 2>/dev/null; then
    # The pane gets the tmux server's environment, not this shell's, so
    # COMMAND needs absolute paths.
    tmux new-session -d -s "${session}" -c "${start_dir}" "$@"
    tmux set-option -t "${session}" status off
    tmux set-option -t "${session}" prefix None
fi

exec env -u TMUX tmux -S "${TMUX%%,*}" attach-session -t "=${session}"
