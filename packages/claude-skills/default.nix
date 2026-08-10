{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude-code.nix.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-08-07";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "f17010c9bb483898c1d9c9f42dde2b3a98889434";
    hash = "sha256-vTqAu8eRY+8ymbf065SWHHjNX/li3SOR+sWq1npteTM=";
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
