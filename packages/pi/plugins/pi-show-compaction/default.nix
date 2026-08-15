{
  runCommandLocal,
}:

# Shows the full compaction summary in the chat after each compaction.
# Local source, so no pin to track — just a store copy for pi.nix to load
# with `-e`.
runCommandLocal "pi-show-compaction" { } ''
  install -Dm444 ${./index.ts} $out/index.ts
''
