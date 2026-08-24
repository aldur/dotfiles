{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude-code.nix.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-08-21";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "3b3fad96af16a10759d930941b4520ba0c40edae";
    hash = "sha256-nVid8vENmLDh7ffDqh+bJbEWtXcVltA0qa2rItmniZM=";
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
