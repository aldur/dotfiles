{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Anthropic's first-party skills, pointed at by modules/home/claude-code.nix.
stdenvNoCC.mkDerivation {
  pname = "claude-skills";
  version = "0-unstable-2026-09-03";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
    hash = "sha256-sjgPv9tZZVTXPxZWaCOc7JwFceNn3C1ghy8mSHqgqB8=";
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
