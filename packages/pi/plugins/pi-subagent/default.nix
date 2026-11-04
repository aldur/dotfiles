{
  lib,
  runCommandLocal,
  nodejs,
  patch,
  pi-coding-agent,
}:

runCommandLocal "pi-subagent-${pi-coding-agent.version}"
  {
    version = pi-coding-agent.version;
    nativeBuildInputs = [ patch ];
  }
  ''
    pi_root="$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/extensions/loader.js')")/../../.."
    mkdir -p "$out"
    install -m444 "$pi_root"/examples/extensions/subagent/{index,agents}.ts "$out"
    patch -d "$out" -p1 < ${./sessions.patch}
    ${lib.getExe nodejs} --no-warnings ${./check.mjs} "$out/index.ts" "$pi_root"
  ''
