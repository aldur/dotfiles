{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "683bc88e56f3e09ba94f7055977f3d3aa499f202";
    hash = "sha256-APw+xMKqRvkLnuQxttiyyIeylrIMSxZovQnw3xEl1C4=";
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
