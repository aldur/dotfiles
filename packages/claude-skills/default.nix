{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude-code.nix.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-08-13";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "f6656c1256d5a8adfa37db9110046ef20bac644c";
    hash = "sha256-5/0f5AnGWX3oM+M9Xm/zSmooz11+S1YRdFPmAX+DXi0=";
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
