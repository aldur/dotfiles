{
  tree-sitter-grammars,
  fetchFromGitHub,
}:

let
  overrideUntilUpgrade = import ../../../utils/override-until-upgrade.nix;
in
# Clarity is not one of nvim-treesitter's bundled grammars and `clarity.nvim`
# ships only the queries, so the parser has to come from somewhere else.
#
# nixpkgs does carry the grammar, but on a rev far behind the queries
# clarity.nvim now expects. Override just the source so nixpkgs keeps owning
# the build (patches, flags, the tree-sitter it is built against); CI bumps
# this alongside clarity.nvim.
overrideUntilUpgrade {
  package = tree-sitter-grammars.tree-sitter-clarity;
  version = "0.0.5-unstable-2025-11-17";
  note = "Drop packages/lazyvim/plugins/tree-sitter-clarity.nix, and its leg in .github/workflows/update-pinned-packages.yml, if nixpkgs' grammar has caught up with clarity.nvim's queries.";

  replacement = tree-sitter-grammars.tree-sitter-clarity.overrideAttrs (_: {
    version = "0.0.5-unstable-2026-07-27";

    src = fetchFromGitHub {
      owner = "xlittlerag";
      repo = "tree-sitter-clarity";
      rev = "f3b7520fa336e877fc7bb180902e325d465da052";
      hash = "sha256-C+pWyVQC0gtU2VO2lkecijbNIKPbqEks0V6vhfN/oso=";
    };
  });
}
