if [[ -z "${TMUX:-}" ]]; then
    echo "tmux-palette: must be run inside a tmux session" >&2
    exit 1
fi

# Each entry: "<label>\t<tmux command>".
# The command is passed to `tmux` via eval, so `\;` chains tmux commands.
entries=(
    $'Toggle timestamped pane logging\tif-shell -F \'#{pane_pipe}\' \'pipe-pane ; display-message "Pane logging stopped"\' "pipe-pane -o \\"exec cat | ts \'[%Y-%m-%d %H:%M:%S]\' >> /tmp/tmux-#S-#I-#P.log\\" ; display-message -d 5000 \'Logging to /tmp/tmux-#S-#I-#P.log\'"'
    $'Capture pane → nvim\tcapture-pane -JS - \\; save-buffer /tmp/tmux-capture.txt \\; delete-buffer \\; display-popup -E -w 90% -h 90% -d \'#{pane_current_path}\' \'nvim /tmp/tmux-capture.txt\''
    $'Lazygit (popup)\tdisplay-popup -E -w 90% -h 90% -d \'#{pane_current_path}\' lazygit'
    $'Toggle synchronize-panes\tset-window-option synchronize-panes'
    $'Toggle silence monitoring (10s)\tif-shell -F \'#{E:monitor-silence}\' \'setw monitor-silence 0 ; display-message "Silence monitoring off"\' \'setw monitor-silence 10 ; display-message "Silence monitoring on (10s)"\''
    $'Kill other panes\tkill-pane -a'
    $'Clear scrollback + screen\tsend-keys C-l \\; clear-history'
    $'Rename window\tcommand-prompt -p "window:" "rename-window %%"'
    $'Rename session\tcommand-prompt -p "session:" "rename-session %%"'
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
