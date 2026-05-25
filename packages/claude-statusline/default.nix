{
  writeShellApplication,
  jq,
  git,
}:

writeShellApplication {
  name = "claude-statusline";
  runtimeInputs = [
    jq
    git
  ];
  text = builtins.readFile ./claude-statusline.sh;
}
