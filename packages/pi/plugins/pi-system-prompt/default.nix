{
  runCommandLocal,
}:

# Adds a /system-prompt command that shows the current system prompt in
# an ephemeral editor view. Local source, so no pin to track — just a
# store copy for pi.nix to load with `-e`.
runCommandLocal "pi-system-prompt" { } ''
  install -Dm444 ${./index.ts} $out/index.ts
''
