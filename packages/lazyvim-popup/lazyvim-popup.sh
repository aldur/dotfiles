# Persistent, per-tmux-window LazyVim popup.
#
# Run from a tmux `display-popup`. Rather than launching a throwaway nvim that
# dies with the popup, this attaches to a detached, per-window tmux session that
# owns the nvim process. Backgrounding the popup (q in nvim, which runs
# `tmux detach-client`) leaves that session running, so the next summon
# reattaches with every buffer and cursor position intact. Quitting nvim
# (:qa) ends the session, so the following summon starts fresh.
#
# Usage:
#   lazyvim-popup                 # per-window editing session (prefix + e)
#   lazyvim-popup KIND [FILE]     # a distinct per-window session named after
#                                 # KIND, opening FILE. On reattach FILE is
#                                 # reloaded so a re-run shows fresh content —
#                                 # the capture-pane palette entry uses this.
#
# KIND/FILE are passed as literal args (no tmux formats), so they survive fine:
# it's only "#{…}" formats that tmux refuses to expand in a popup shell-command.
kind=${1:-}
file=${2:-}

# Resolve the invoking window and its cwd from inside the popup. We can't take
# them as args because tmux does NOT format-expand a display-popup shell-command
# ("#{window_id}" would arrive literally). We must target the *originating
# session* explicitly: $TMUX's last field is its id ("$N"), and that session's
# active window is the pane the popup was opened over. A bare display-message
# instead resolves to the server's most-recently-active window — which a
# backgrounded popup session steals, so re-runs would reattach to the wrong
# window (and never reattach at all).
origin="\$${TMUX##*,}"
window_id=$(tmux display-message -t "$origin" -p '#{window_id}')
start_dir=$(tmux display-message -t "$origin" -p '#{pane_current_path}')

# window_id (e.g. "@5") is unique for the server's lifetime and survives window
# renames and renumbering, so it is a stable per-window key. Drop the "@", which
# only makes `choose-tree` look tidier. KIND namespaces distinct popups (e.g.
# editing vs capture) so they get independent per-window sessions.
session="_lazyvim${kind:+_${kind}}_${window_id#@}"

if tmux has-session -t "=${session}" 2>/dev/null; then
    # Reattaching to a backgrounded session. If a FILE was given, reload it so a
    # re-run shows freshly-captured content instead of the stale buffer. q only
    # backgrounds from normal mode, so nvim is in normal mode here; `:edit!`
    # force-reloads from disk.
    [ -n "$file" ] && tmux send-keys -t "${session}" ":edit! ${file}" Enter
else
    # LAZYVIM_BIN comes from the wrapper (default.nix): the session command
    # runs with the tmux *server's* environment, whose PATH may not include
    # lazyvim, so prefer the absolute path baked in at build time.
    nvim_cmd=("$LAZYVIM_BIN")
    [ -n "$file" ] && nvim_cmd+=("$file")
    tmux new-session -d -s "${session}" -c "${start_dir}" -e NVIM_POPUP=1 "${nvim_cmd[@]}"
    # Popup-only session: drop the status line so nvim fills the popup, and
    # disable the prefix so every key reaches nvim (we background via the q
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
