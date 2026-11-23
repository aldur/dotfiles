{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-11-16";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "e4bb5d960d87126ff3b3a8af1a104b7db67560ba";
    hash = "sha256-Gr9LatjawHHK9uKpoclWoiDHZ0NTpP3/4Pmeatl8p/Q=";
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
