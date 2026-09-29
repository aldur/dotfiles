{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-09-24";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "33375500bcea98d610eb30ce10ac4e59b89c390d";
    hash = "sha256-xUs7UX8pOcZwR0okaSbI/f8EE5F4Zi/BUd+nIZNafPc=";
  };

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  # Ship the skills exactly as upstream wrote them: fixup would rewrite the
  # `#!/bin/bash` shebangs in skills/web-artifacts-builder/scripts to point at
  # a store bash, which is not what Claude Code reads them as.
  dontFixup = true;

  # Tracks its default branch; nothing is tagged upstream.
  passthru.updatePin.args = "--version=branch";
}
