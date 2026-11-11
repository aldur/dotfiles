{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

runCommandLocal "pi-subagent" { } ''
  pi_root="$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/extensions/loader.js')")/../../.."
  mkdir -p "$out"
  install -m444 ${./index.ts} "$out/index.ts"
  install -m444 ${./agents.ts} "$out/agents.ts"
  install -m444 ${./LICENSE} "$out/LICENSE"
  ${lib.getExe nodejs} --no-warnings ${../../tests/plugins/pi-subagent.mjs} "$out/index.ts" "$pi_root"
''
