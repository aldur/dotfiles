{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

runCommandLocal "pi-subagent-${pi-coding-agent.version}"
  {
    version = pi-coding-agent.version;
  }
  ''
    pi_root="$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/extensions/loader.js')")/../../.."
    mkdir -p "$out"
    ln -s "$pi_root/examples/extensions/subagent/index.ts" "$out/index.ts"
    ln -s "$pi_root/examples/extensions/subagent/agents.ts" "$out/agents.ts"
    ${lib.getExe nodejs} --no-warnings ${./check.mjs} "$out/index.ts" "$pi_root"
  ''
