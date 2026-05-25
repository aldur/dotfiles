{
  writeShellApplication,
  fzf,
  jq,
  coreutils,
  findutils,
  gawk,
  gnused,
}:

writeShellApplication {
  name = "claude-log";

  runtimeInputs = [
    fzf
    jq
    coreutils
    findutils
    gawk
    gnused
  ];

  text = builtins.readFile ./claude-log.sh;
}
