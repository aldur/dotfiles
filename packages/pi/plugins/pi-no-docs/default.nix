{
  lib,
  runCommandLocal,
  nodejs,
  pi-coding-agent,
}:

# Strips the "Pi documentation" section from pi's default system prompt.
# Local source, so no pin to track — just a store copy for pi.nix to load
# with `-e`.
#
# check.mjs applies the extension's own strip function to the default
# prompt that this pi build produces. When a pi bump rewords the block,
# the build fails here instead of the extension silently keeping the
# block in the prompt.
runCommandLocal "pi-no-docs" { } ''
  ${lib.getExe nodejs} --no-warnings ${./check.mjs} ${./index.ts} \
    "$(find ${pi-coding-agent}/lib -path '*/dist/core/system-prompt.js')"
  install -Dm444 ${./index.ts} $out/index.ts
''
