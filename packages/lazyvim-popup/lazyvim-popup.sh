# Persistent, per-tmux-window LazyVim popup.
#
# Run from a tmux `display-popup`. Rather than launching a throwaway nvim that
# dies with the popup, this attaches to a detached, per-window tmux session that
# owns the nvim process. Backgrounding the popup (esc in nvim, which runs
# `tmux detach-client`) leaves that session running, so the next summon
# reattaches with every buffer and cursor position intact. `q` quits nvim, which
# ends the session, so the following summon starts fresh.
#
# Usage: bind-key e display-popup -E -w 90% -h 90% lazyvim-popup
#
# We resolve the invoking window and its cwd from inside the popup rather than
# taking them as arguments: tmux does NOT format-expand a display-popup
# shell-command, so "#{window_id}" on the command line would arrive literally.
# Inside the popup, `display-message` resolves against the client's active pane,
# which is the underlying pane the popup was opened over.
window_id=$(tmux display-message -p '#{window_id}')
start_dir=$(tmux display-message -p '#{pane_current_path}')

# window_id (e.g. "@5") is unique for the server's lifetime and survives window
# renames and renumbering, so it is a stable per-window key. Drop the "@", which
# only makes `choose-tree` look tidier.
session="_lazyvim_${window_id#@}"

if ! tmux has-session -t "=${session}" 2>/dev/null; then
    tmux new-session -d -s "${session}" -c "${start_dir}" -e NVIM_POPUP=1 lazyvim
    # Popup-only session: drop the status line so nvim fills the popup, and
    # disable the prefix so every key reaches nvim (we background via the esc
    # keymap, not a tmux prefix binding). No "=" exact-match prefix here: unlike
    # has-session/attach-session, set-option rejects it ("no such session: =…").
    # The bare name still resolves exactly — we just created this session.
    tmux set-option -t "${session}" status off
    tmux set-option -t "${session}" prefix None
fi

# Attach. TMUX must be unset so tmux does not refuse to attach "nested" inside
# the popup — but unsetting it also discards which socket the server is on, so
# pass that explicitly via -S (the first field of $TMUX). Without it the attach
# falls back to the default socket and fails whenever the server lives elsewhere
# (e.g. `secureSocket = true`, which puts it under $TMUX_TMPDIR).
exec env -u TMUX tmux -S "${TMUX%%,*}" attach-session -t "=${session}"
