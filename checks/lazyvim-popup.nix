# The tmux popup wrapper (packages/lazyvim-popup) drives a detached,
# per-window session it resolves from $TMUX — logic a build can exercise
# without a terminal. The attach at the end of the script is the one part
# that needs one, so each summon here ends in a failed attach; by then the
# part under test has already run.
#
# What this pins down:
#  * the first summon creates the per-window session and nvim comes up in
#    it with the FILE;
#  * the second summon reattaches and reloads the FILE from disk — from
#    normal mode, whatever mode the popup died in. A killed popup client
#    skips the `q` keymap, so nvim can sit in insert mode with unsaved
#    junk; the reload must not type the ex command into the buffer.
{
  lib,
  runCommand,
  tmux,
  callPackage,
  # The light build boots fastest and carries the popup keymap all the same.
  lazyvim-light,
}:

let
  popup = callPackage ../packages/lazyvim-popup {
    lazyvim-bin = lib.getExe' lazyvim-light "lazyvim-light";
  };

  # Poll rather than sleep: nvim boots in this sandbox in seconds, but a
  # loaded builder can stretch that, and a fixed sleep would only trade
  # flakiness for wall-clock.
  waitForPane = pattern: ''
    found=
    for _ in $(seq 120); do
      if tmux -S "$sock" capture-pane -t "$session" -p | grep -aq ${lib.escapeShellArg pattern}; then
        found=1
        break
      fi
      sleep 1
    done
    if [ -z "$found" ]; then
      echo "pane never showed: ${pattern}"
      tmux -S "$sock" capture-pane -t "$session" -p
      exit 1
    fi
  '';
in
runCommand "lazyvim-popup-check"
  {
    nativeBuildInputs = [
      tmux
      popup
    ];
  }
  ''
    export HOME=$TMPDIR \
      XDG_CONFIG_HOME=$TMPDIR/.config \
      XDG_DATA_HOME=$TMPDIR/.data \
      XDG_STATE_HOME=$TMPDIR/.state
    sock=$TMPDIR/tsock

    # A session standing in for the window the popup covers. On a fresh
    # server it gets id $0 — which is what the faked $TMUX names below.
    tmux -S "$sock" new-session -d -s outer -x 80 -y 24 sleep 600

    # What a real popup inherits: socket, a pid the script never reads,
    # and the originating session's id.
    export TMUX="$sock,0,0"

    printf 'original content\n' > "$TMPDIR/note.txt"

    # First summon: creates the session, then fails to attach (no tty).
    lazyvim-popup capture "$TMPDIR/note.txt" || true

    session=$(tmux -S "$sock" list-sessions -F '#{session_name}' | grep '^_lazyvim_capture_')
    if [ -z "$session" ]; then
      echo "no popup session created"
      tmux -S "$sock" list-sessions
      exit 1
    fi

    ${waitForPane "original content"}

    # A user mid-edit when the popup client dies: insert mode, unsaved junk.
    tmux -S "$sock" send-keys -t "$session" i "user typing"

    printf 'fresh content\n' > "$TMPDIR/note.txt"

    # Second summon: the reattach branch reloads FILE, then fails to attach.
    lazyvim-popup capture "$TMPDIR/note.txt" || true

    ${waitForPane "fresh content"}
    if tmux -S "$sock" capture-pane -t "$session" -p | grep -aq "user typing"; then
      echo "reload left the insert-mode junk in the buffer"
      tmux -S "$sock" capture-pane -t "$session" -p
      exit 1
    fi

    tmux -S "$sock" kill-server || true
    touch $out
  ''
