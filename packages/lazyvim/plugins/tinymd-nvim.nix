{
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "tinymd.nvim";
  version = "0-unstable-2025-01-07";

  src = fetchFromGitHub {
    owner = "aldur";
    repo = "tinymd.nvim";
    rev = "f1caf374827de0e01a7bc90bdb6761fcbfab3b1f";
    hash = "sha256-Sl+L3fQMs/YsVllDuJpmwFNGtaDeta5okH3Kl5+xI1g=";
  };

  # Tracks its default branch; nothing is tagged upstream.
  passthru.updatePin.args = "--version=branch";
}
