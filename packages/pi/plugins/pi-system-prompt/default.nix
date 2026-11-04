{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

runCommandLocal "pi-system-prompt" { } ''
  mkdir -p $out
  substitute ${./index.ts} $out/index.ts \
    --replace-fail '../pi-no-docs/index.ts' '${../pi-no-docs/index.ts}'
  ${lib.getExe nodejs} --no-warnings ${../../tests/plugins/pi-system-prompt.mjs} $out/index.ts \
    "$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/model-registry.js')")/../.." \
    ${../pi-no-docs/index.ts}
''
