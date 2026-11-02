{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-10-28";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "ca45fc496a3436251f191354091d557da31c15b5";
    hash = "sha256-MkCOANBAqCc1WmNf7S8PsyAphGJAIzEXGyCm8RrCR9M=";
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
