{
  writeShellApplication,
  tmux,
}:

writeShellApplication {
  name = "tmux-popup-session";

  runtimeInputs = [
    tmux
  ];

  text = builtins.readFile ./tmux-popup-session.sh;

  # Resolve the popup's own session live (#S) and target it with -s: a bare
  # `detach-client` would pick the outer terminal and drop the user out of
  # tmux entirely.
  passthru.hide = writeShellApplication {
    name = "tmux-popup-hide";
    runtimeInputs = [ tmux ];
    text = ''tmux detach-client -s "$(tmux display-message -p '#S')"'';
  };
}
