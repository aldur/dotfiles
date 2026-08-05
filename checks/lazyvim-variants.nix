{
  lib,
  runCommand,
  closureInfo,
  git,
  # The two editor builds, bound by ./default.nix.
  lazyvim,
  lazyvim-light,
}:

# The editor is split into nixCats categories (packages/lazyvim): `general`
# is a survival kit and the language tooling rides per-language categories.
# This pins the split down from both sides — the full build must keep every
# heavy tool, the light build must never regain one — and starts each
# headless, which catches lua errors and any plugin lazy.nvim would try (and,
# sandboxed, fail) to fetch from the network.

let
  fullClosure = closureInfo { rootPaths = [ lazyvim ]; };
  lightClosure = closureInfo { rootPaths = [ lazyvim-light ]; };

  # Name fragments of the tooling that must separate the two variants.
  heavy = [
    "basedpyright"
    "markdown-preview"
    "pandoc-cli"
    "harper"
    "marksman"
    "dotnet"
  ];

  # Build residue that must appear in neither: npm dependency caches leaked
  # through node-gyp's config.gypi, and toolchains the editor stopped
  # bundling (projects bring their own through direnv).
  residue = [
    "npm-deps"
    "rustc-bootstrap"
    "-rustc-"
    "cargo-"
    # The editor ships no interpreter runtimes: python came in through
    # node-gyp leftovers, full git and glib-dev; perl through full git.
    # `-perl-5`, not `perl-`: the tree-sitter perl grammar is legitimate.
    "python3-"
    "-perl-5"
  ];
in
runCommand "lazyvim-variants"
  {
    # lazy.nvim shells out to git for dev-mode plugins.
    nativeBuildInputs = [ git ];
  }
  ''
    export HOME=$TMPDIR \
      XDG_CONFIG_HOME=$TMPDIR/.config \
      XDG_DATA_HOME=$TMPDIR/.data \
      XDG_STATE_HOME=$TMPDIR/.state

    ${lib.getExe' lazyvim "lazyvim"} --headless "+lua print('full: started')" +qa
    ${lib.getExe' lazyvim-light "lazyvim-light"} --headless "+lua print('light: started')" +qa

    ${lib.concatMapStringsSep "\n" (p: ''
      grep -q ${lib.escapeShellArg p} ${fullClosure}/store-paths \
        || { echo "full build lost ${p}"; exit 1; }
      if grep -q ${lib.escapeShellArg p} ${lightClosure}/store-paths; then
        echo "light build gained ${p}"; exit 1
      fi
    '') heavy}

    ${lib.concatMapStringsSep "\n" (p: ''
      for closure in ${fullClosure} ${lightClosure}; do
        if grep -q ${lib.escapeShellArg p} "$closure"/store-paths; then
          echo "build residue ${p} crept back in ($closure)"; exit 1
        fi
      done
    '') residue}

    touch $out
  ''
