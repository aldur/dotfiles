{
  writeShellApplication,
  fzf,
}:

writeShellApplication {
  name = "tmux-palette";

  runtimeInputs = [
    fzf
  ];

  text = builtins.readFile ./tmux-palette.sh;
}
