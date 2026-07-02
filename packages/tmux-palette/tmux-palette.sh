if [[ -z "${TMUX:-}" ]]; then
    echo "tmux-palette: must be run inside a tmux session" >&2
    exit 1
fi

# Pane logs and captures contain whatever is on screen — routinely secrets.
# Keep them in a per-user 0700 dir instead of world-readable,
# symlink-attackable /tmp. XDG_RUNTIME_DIR (Linux) and TMPDIR (macOS) are
# both per-user 0700; only fall back to a fresh mktemp dir if neither is set.
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    palette_dir="$XDG_RUNTIME_DIR/tmux-palette"
    mkdir -p "$palette_dir"
    chmod 700 "$palette_dir"
elif [[ -n "${TMPDIR:-}" ]]; then
    palette_dir="${TMPDIR%/}/tmux-palette-$UID"
    mkdir -p "$palette_dir"
    chmod 700 "$palette_dir"
else
    palette_dir=$(mktemp -d /tmp/tmux-palette.XXXXXX)
fi

# Each entry: "<label>\t<tmux command>".
# The command is passed to `tmux` via eval, so `\;` chains tmux commands.
entries=(
    $'Toggle timestamped pane logging\tif-shell -F \'#{pane_pipe}\' \'pipe-pane ; display-message "Pane logging stopped"\' "pipe-pane -o \\"exec cat | ts \'[%Y-%m-%d %H:%M:%S]\' >> '"$palette_dir"$'/tmux-#S-#I-#P.log\\" ; display-message -d 5000 \'Logging to '"$palette_dir"$'/tmux-#S-#I-#P.log\'"'
    $'Capture pane → nvim\tcapture-pane -JS - \\; save-buffer '"$palette_dir"$'/capture.txt \\; delete-buffer \\; display-popup -E -w 90% -h 90% \'lazyvim-popup capture '"$palette_dir"$'/capture.txt\''
    $'Lazygit (popup)\tdisplay-popup -E -w 90% -h 90% -d \'#{pane_current_path}\' lazygit'
    $'Toggle synchronize-panes\tset-window-option synchronize-panes'
    $'Toggle silence monitoring (10s)\tif-shell -F \'#{E:monitor-silence}\' \'setw monitor-silence 0 ; display-message "Silence monitoring off"\' \'setw monitor-silence 10 ; display-message "Silence monitoring on (10s)"\''
    $'Kill other panes\tkill-pane -a'
    $'Clear scrollback + screen\tsend-keys C-l \\; clear-history'
    $'Rename window\tcommand-prompt -p "window:" "rename-window %%"'
    $'Rename session\tcommand-prompt -p "session:" "rename-session %%"'
    $'Rename pane (sticky, empty clears)\tcommand-prompt -p "pane:" "set-option -p @pane_name \'%%\'"'
    $'Toggle pane border labels\tif-shell -F \'#{==:#{E:pane-border-status},off}\' \'set-window-option pane-border-status top ; display-message "Pane border labels: on"\' \'set-window-option pane-border-status off ; display-message "Pane border labels: off"\''
    $'Break pane to new window\tbreak-pane'
    $'Show all keybindings\tdisplay-popup -E -w 80% -h 80% "tmux list-keys | fzf --reverse --no-sort --prompt=\'keybind> \'"'
)

choice=$(printf '%s\n' "${entries[@]}" \
    | fzf -d $'\t' --with-nth=1 --reverse --prompt='tmux> ' \
          --preview 'echo {2}' --preview-window=down:1:wrap \
          --header='⏎ run · esc cancel')

[[ -z "$choice" ]] && exit 0

cmd=${choice#*$'\t'}

# Defer the tmux invocation until after this popup closes: nested
# `display-popup` calls are silently dropped, and `command-prompt` overlays
# don't render over an active popup either. `run-shell -b` queues a shell
# command that fires once the palette is gone, so the dispatched action
# always runs against the original calling pane.
runner=$(mktemp /tmp/tmux-palette.XXXXXX)
printf 'tmux %s\nrm -f -- %q\n' "$cmd" "$runner" > "$runner"
tmux run-shell -b "bash $runner"
