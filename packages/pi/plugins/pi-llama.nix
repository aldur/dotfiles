{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
  pi-coding-agent,
}:

# Hugging Face's llama.cpp provider for pi. Wrapped in a derivation (rather
# than exposing fetchFromGitHub directly) so it carries a `version` that
# nix-update can bump in CI.
stdenvNoCC.mkDerivation {
  pname = "pi-llama";
  version = "0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "pi-llama";
    rev = "a04d8549b80fd0260f8bd19fe5fe6f7d36d21c7d";
    hash = "sha256-CyOPffy2425+Ea7PzhWlNqrkiLTzxNx9h7I86HzOD/g=";
  };

  # Prefer advertised reasoning efforts and defaults; retain template-based
  # discovery for llama.cpp. Read metadata before the first prompt, bound
  # catalog requests, and cancel requests when the user changes models.
  # Drop once merged upstream: https://github.com/huggingface/pi-llama
  patches = [
    ./pi-llama-reasoning-effort.patch
    ./pi-llama-startup-discovery.patch
    ./pi-llama-model-capabilities.patch
    ./pi-llama-startup-status.patch
    ./pi-llama-spinner.patch
    ./pi-llama-errors.patch
  ];

  # llama.cpp has no output-token cap (generation is bounded only by n_ctx),
  # but the plugin clamps maxTokens to a hardcoded 16384, truncating long
  # thinking-model responses mid-turn. Report the backend's actual bound
  # instead; pi's compaction.reserveTokens owns the headroom policy.
  # Drop once fixed upstream: https://github.com/huggingface/pi-llama
  postPatch = ''
    substituteInPlace index.ts \
      --replace-fail "Math.min(DEFAULT_MAX_TOKENS, contextWindow)" "contextWindow" \
      --replace-fail "Math.min(DEFAULT_MAX_TOKENS, nCtx)" "nCtx"
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${lib.getExe nodejs} --no-warnings ${../tests/plugins/pi-llama.mjs} "$PWD/index.ts" \
      "$(dirname "$(find ${pi-coding-agent}/lib -path '*/dist/core/model-registry.js')")/../.."
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  passthru.updatePin = {
    # Tracks its default branch; nothing is tagged upstream.
    args = "--version=branch";
    # pi loads <plugin>/index.ts, so building the wrapper is not enough.
    verify = "nix build .#pi -L && test -f \"$(nix build .#pi.plugins.pi-llama -L --print-out-paths)/index.ts\"";
  };
}
