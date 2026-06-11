{
  writeShellApplication,
  fzf,
  jq,
  jaq,
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
    jaq # faster jq (Rust) used for the hot session-list extraction
    coreutils
    findutils
    gawk
    gnused
  ];

  text = builtins.readFile ./claude-log.sh;
}
