{
  stdenvNoCC,
  fetchFromGitHub,
}:

# Hugging Face's llama.cpp provider for pi. Wrapped in a derivation (rather
# than exposing fetchFromGitHub directly) so it carries a `version` that
# nix-update can bump in CI.
stdenvNoCC.mkDerivation {
  pname = "pi-llama";
  version = "0-unstable-2026-07-06";

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "pi-llama";
    rev = "8a876fca45c7824a50cd74f01ea11e0bab7964a2";
    hash = "sha256-5cTimbW+wLYiAUsqoNUi9AbArrWUR2Mzd+22zkwrTlg=";
  };

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';
}
