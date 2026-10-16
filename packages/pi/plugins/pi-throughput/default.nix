{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

# Local source, loaded by pi.nix with -e. Check both the display and the raw
# stream hook against the same Pi dependencies that the wrapper runs.
runCommandLocal "pi-throughput" { } ''
  ${lib.getExe nodejs} --no-warnings ${./check.mjs} ${./index.ts} \
    "$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/model-registry.js')")/../.." \
    ${../pi-statusline/index.ts}
  install -Dm444 ${./index.ts} $out/index.ts
''
