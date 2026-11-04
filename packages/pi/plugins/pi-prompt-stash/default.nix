{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

runCommandLocal "pi-prompt-stash" { } ''
  ${lib.getExe nodejs} --no-warnings ${../../tests/plugins/pi-prompt-stash.mjs} ${./index.ts} \
    "$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/model-registry.js')")/../.."
  install -Dm444 ${./index.ts} $out/index.ts
''
