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
  version = "0-unstable-2026-09-23";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "pi-llama";
    rev = "e03e07be02abdf0f7ac52032e2050e19e2bdd5c7";
    hash = "sha256-Q63awf1R2Un2Is0UfxFFTKH0FKeayP5+5/MhpzVNJn0=";
  };

  # Only use Qwen's effort levels when the template lists them. Read local
  # model settings before the first prompt. Limit model-list requests to one
  # second, and cancel old requests when the user changes models.
  # Drop once merged upstream: https://github.com/huggingface/pi-llama
  patches = [
    ./pi-llama-reasoning-effort.patch
    ./pi-llama-startup-discovery.patch
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
    ${lib.getExe nodejs} --no-warnings ${./pi-llama-check.mjs} "$PWD/index.ts" \
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
