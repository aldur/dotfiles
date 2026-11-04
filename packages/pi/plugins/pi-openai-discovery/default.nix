{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
  modelsCatalog,
}:

runCommandLocal "pi-openai-discovery" { } ''
  mkdir -p $out
  substitute ${./index.ts} $out/index.ts --replace-fail '@catalogPath@' '${modelsCatalog}/catalog.json'
  ${lib.getExe nodejs} --no-warnings ${../../tests/plugins/pi-openai-discovery.mjs} $out/index.ts \
    "$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/model-registry.js')")/../.."
''
