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
# sandboxed, fail) to fetch from the network. The full build must also
# *attach* one server per stripped runtime path, not merely ship it.

let
  fullClosure = closureInfo { rootPaths = [ lazyvim ]; };
  lightClosure = closureInfo { rootPaths = [ lazyvim-light ]; };

  # Closure budgets in MiB, ~10% above the measured sizes (2026-08: full
  # ~2340, light ~280). Named residue below catches known offenders; this
  # catches the unknown ones — a plugin or tool quietly dragging in a
  # runtime. Grows legitimately? Re-measure and raise the budget here.
  maxMiB = {
    full = 2600;
    light = 320;
  };

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
    # git's translation machinery and contrib scripts (see runtime.nix).
    "gettext"
    "bash-interactive"
    # Spell files neovim can never load: 'encoding' is hardwired to utf-8.
    "latin1"
    # The full nodejs join and node's compiled-in build headers; the editor
    # ships the runtime node only (see nodejs-slim-runtime in the overlay).
    "corepack"
    "-npm"
    "-dev$"
  ];

  # One file per runtime that overlays/slim.nix rewires: jsonls runs
  # through vscode-langservers' binary wrappers around the stripped node,
  # vtsls and basedpyright are npm bundles re-pointed at it, and the
  # solidity server rides the same path. Attaching exercises the whole
  # chain — lspconfig wiring, the wrapper PATH, and the node those servers
  # exec — where mere presence in the closure would not.
  attach = [
    {
      ext = "json";
      text = ''{"name":"x"}'';
      server = "jsonls";
    }
    {
      ext = "ts";
      text = "const a: number = 1;";
      server = "vtsls";
    }
    {
      ext = "py";
      text = "x = 1";
      server = "basedpyright";
    }
    {
      ext = "sol";
      text = "pragma solidity ^0.8.0;\ncontract C {}";
      server = "solidity_ls_nomicfoundation";
    }
  ];

  # Announce every attach, quit on the expected one; time out loudly (cq)
  # rather than hang the build.
  attachLua =
    server:
    "vim.api.nvim_create_autocmd('LspAttach',{callback=function(a)"
    + " local c=vim.lsp.get_client_by_id(a.data.client_id)"
    + " io.write('ATTACHED: '..c.name..'\\n')"
    + " if c.name=='${server}' then vim.schedule(function() vim.cmd('qa!') end) end"
    + " end}); vim.defer_fn(function() io.write('no attach\\n') vim.cmd('cq') end, 120000)";
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

    ${lib.concatMapStringsSep "\n" (t: ''
      printf '%s\n' ${lib.escapeShellArg t.text} > "$TMPDIR/attach.${t.ext}"
      ${lib.getExe' lazyvim "lazyvim"} --headless \
        ${lib.escapeShellArg "+lua ${attachLua t.server}"} \
        "+edit $TMPDIR/attach.${t.ext}" 2>&1 | grep -a "ATTACHED: ${t.server}" \
        || { echo "${t.server} did not attach to attach.${t.ext}"; exit 1; }
    '') attach}

    ${lib.concatMapStringsSep "\n" (p: ''
      grep -q -e ${lib.escapeShellArg p} ${fullClosure}/store-paths \
        || { echo "full build lost ${p}"; exit 1; }
      if grep -q -e ${lib.escapeShellArg p} ${lightClosure}/store-paths; then
        echo "light build gained ${p}"; exit 1
      fi
    '') heavy}

    # `-e` keeps grep from reading leading-dash fragments as options — an
    # error `if` would otherwise swallow, silently retiring the assertion.
    ${lib.concatMapStringsSep "\n" (p: ''
      for closure in ${fullClosure} ${lightClosure}; do
        if grep -q -e ${lib.escapeShellArg p} "$closure"/store-paths; then
          echo "build residue ${p} crept back in ($closure)"; exit 1
        fi
      done
    '') residue}

    ${lib.concatMapStringsSep "\n"
      (
        {
          name,
          closure,
          max,
        }:
        ''
          sizeMiB=$(( $(cat ${closure}/total-nar-size) / 1024 / 1024 ))
          echo "${name} closure: $sizeMiB MiB (budget ${toString max} MiB)"
          if [ "$sizeMiB" -gt ${toString max} ]; then
            echo "${name} closure outgrew its budget"; exit 1
          fi
        ''
      )
      [
        {
          name = "full";
          closure = fullClosure;
          max = maxMiB.full;
        }
        {
          name = "light";
          closure = lightClosure;
          max = maxMiB.light;
        }
      ]
    }

    touch $out
  ''
