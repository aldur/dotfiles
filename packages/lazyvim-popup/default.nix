{
  writeShellApplication,
  tmux,
  lazyvim-bin ? "lazyvim",
}:

writeShellApplication {
  name = "lazyvim-popup";

  runtimeInputs = [
    tmux
  ];

  runtimeEnv = {
    LAZYVIM_BIN = lazyvim-bin;
  };

  text = builtins.readFile ./lazyvim-popup.sh;
}
