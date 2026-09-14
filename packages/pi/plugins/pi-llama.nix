{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Hugging Face's llama.cpp provider for pi. Wrapped in a derivation (rather
# than exposing fetchFromGitHub directly) so it carries a `version` that
# nix-update can bump in CI.
stdenvNoCC.mkDerivation {
  pname = "pi-llama";
  version = "0-unstable-2026-09-11";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "pi-llama";
    rev = "a14d9e8846c9fae4a3021eb0400be108484c97b7";
    hash = "sha256-UFQgtuL+QFR1mg5/dCQ1b04xgjfC+FUJN+pZD4MeitI=";
  };

  # A chat template that reads reasoning_effort accepts graded thinking
  # levels (for example Qwen 3.8), but the plugin only sniffs the boolean
  # enable_thinking and caps the UI at off/medium. Sniff reasoning_effort
  # too and register Pi's generic "chat-template" format for it.
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
