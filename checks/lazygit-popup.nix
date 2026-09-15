# The lazygit popup wrapper (packages/lazygit-popup) drives a detached,
# per-window session it resolves from $TMUX, like lazyvim-popup. A control-mode
# client (`tmux -C`) stands in for the popup: it attaches without a terminal,
# so the detach that `q` runs is observable here.
#
# What this pins down:
#  * the first summon creates the per-window session and lazygit comes up in
#    it with the popup config;
#  * `q` detaches the popup client and leaves lazygit running, and the next
#    summon reattaches to that session instead of creating another;
#  * `Q` still quits lazygit, which ends the session.
{
  lib,
  runCommand,
  tmux,
  git,
  callPackage,
}:

let
  popup = callPackage ../packages/lazygit-popup {
    settings = {
      disableStartupPopups = true;
      update.method = "never";
    };
  };

  # Poll rather than sleep: a loaded builder stretches every step, and a
  # fixed sleep would only trade flakiness for wall-clock.
  waitFor = what: cond: ''
    found=
    for _ in $(seq 120); do
      if ${cond}; then
        found=1
        break
      fi
      sleep 1
    done
    if [ -z "$found" ]; then
      echo "timed out waiting for: ${what}"
      tmux -S "$sock" list-sessions || true
      tmux -S "$sock" capture-pane -t "$session" -p || true
      exit 1
    fi
  '';

  popupSessions = ''tmux -S "$sock" list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^_lazygit_' || true'';
  clients = ''tmux -S "$sock" list-clients -t "=$session" 2>/dev/null | wc -l'';
in
runCommand "lazygit-popup-check"
  {
    nativeBuildInputs = [
      tmux
      git
      popup
    ];
  }
  ''
    export HOME=$TMPDIR \
      XDG_CONFIG_HOME=$TMPDIR/.config \
      XDG_DATA_HOME=$TMPDIR/.data \
      XDG_STATE_HOME=$TMPDIR/.state
    sock=$TMPDIR/tsock

    repo=$TMPDIR/repo
    git init -q "$repo"
    git -C "$repo" -c user.name=check -c user.email=check@example.invalid \
      commit -q --allow-empty -m "popup check"

    # A session standing in for the window the popup covers, with its pane
    # in the repo. On a fresh server it gets id $0 — which is what the faked
    # $TMUX names below.
    tmux -S "$sock" new-session -d -s outer -x 120 -y 40 -c "$repo" sleep 600

    # The pane process starts after new-session returns. Until it has
    # changed into the repo, #{pane_current_path} reports the directory of
    # the tmux server, and the popup would start lazygit there. A real
    # window has run for a long time before a summon, so only this check
    # can hit that.
    ${waitFor "the outer pane to enter the repo" ''[ "$(tmux -S "$sock" display-message -t '$0' -p '#{pane_current_path}')" = "$repo" ]''}

    # What a real popup inherits: socket, a pid the script never reads,
    # and the originating session's id.
    export TMUX="$sock,0,0"

    # First summon: creates the session, then fails to attach (no tty).
    lazygit-popup || true

    session=$(tmux -S "$sock" list-sessions -F '#{session_name}' | grep '^_lazygit_')
    if [ -z "$session" ]; then
      echo "no popup session created"
      tmux -S "$sock" list-sessions
      exit 1
    fi

    ${waitFor "lazygit to show the repo" ''tmux -S "$sock" capture-pane -t "$session" -p | grep -aq "popup check"''}

    # The popup client. Control mode reads commands from stdin and leaves at
    # EOF, so keep that pipe open for the duration.
    (sleep 600 | tmux -S "$sock" -C attach-session -t "=$session" > /dev/null) &
    ${waitFor "the popup client to attach" ''[ "$(${clients})" -eq 1 ]''}

    tmux -S "$sock" send-keys -t "$session" q
    ${waitFor "q to detach the popup client" ''[ "$(${clients})" -eq 0 ]''}

    if ! tmux -S "$sock" has-session -t "=$session" 2>/dev/null; then
      echo "q quit lazygit instead of backgrounding it"
      exit 1
    fi

    # Second summon: reattaches to the same session, then fails to attach.
    lazygit-popup || true
    if [ "$(${popupSessions})" -ne 1 ]; then
      echo "the second summon did not reuse the popup session"
      tmux -S "$sock" list-sessions
      exit 1
    fi

    tmux -S "$sock" send-keys -t "$session" Q
    ${waitFor "Q to quit lazygit" ''! tmux -S "$sock" has-session -t "=$session" 2>/dev/null''}

    tmux -S "$sock" kill-server || true
    touch $out
  ''
