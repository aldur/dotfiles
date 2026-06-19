{
  writeShellApplication,
  tmux,
}:

writeShellApplication {
  name = "lazyvim-popup";

  runtimeInputs = [
    tmux
  ];

  text = builtins.readFile ./lazyvim-popup.sh;
}
