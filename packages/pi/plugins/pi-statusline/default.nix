{
  runCommandLocal,
}:

# Claude Code's statusline, for pi: the same line packages/claude-statusline
# prints, rendered by an extension that replaces pi's footer. Local source, so
# no pin to track — just a store copy for pi.nix to load with `-e`.
runCommandLocal "pi-statusline" { } ''
  install -Dm444 ${./index.ts} $out/index.ts
''
