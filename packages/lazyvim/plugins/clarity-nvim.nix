{
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "clarity.nvim";
  version = "0.3.0-unstable-2026-08-28";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "clarity.nvim";
    rev = "df3f2decf4dafa24f70e3e51388e4780182496b0";
    hash = "sha256-27IIR4OujcRwqtURkZ2K9NgEzdf9X59L7YDikH5Cd5I=";
  };

  doCheck = false; # Missing runtime dependencies for "require" check

  # Tracks its default branch; nothing is tagged upstream.
  passthru.updatePin.args = "--version=branch";
}
