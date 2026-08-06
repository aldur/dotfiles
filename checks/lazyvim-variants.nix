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

  # Name fragments of the tooling that must separate the two variants.
  # (No "dotnet": marksman's runtime rides inside its own store path —
  # see overlays/slim.nix — and the attach test proves it boots.)
  heavy = [
    "basedpyright"
    "markdown-preview"
    "pandoc-cli"
    "harper"
    "marksman"
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
    # rust-analyzer's wrapper would pin this stdlib-source fallback;
    # projects bring their own toolchain through direnv.
    "rust-lib-src"
  ];

  # One file per runtime that overlays/slim.nix rewires: jsonls runs
  # through vscode-langservers' binary wrappers around the stripped node,
  # vtsls and basedpyright are npm bundles re-pointed at it, and the
  # solidity server rides the same path. Attaching exercises the whole
  # chain — lspconfig wiring, the wrapper PATH, and the node those servers
  # exec — where mere presence in the closure would not. For the two
  # servers whose packages are pruned hardest, attach is not enough: the
  # file carries a type error and the server must *diagnose* it, proving
  # vtsls still spawns tsserver from the kept typescript package and
  # basedpyright still reads its embedded typeshed.
  attach = [
    {
      ext = "json";
      text = ''{"name":"x"}'';
      server = "jsonls";
      diag = false;
    }
    {
      ext = "ts";
      text = ''const a: number = "wrong";'';
      server = "vtsls";
      diag = true;
    }
    {
      ext = "py";
      text = ''x: int = "wrong"'';
      server = "basedpyright";
      diag = true;
    }
    {
      ext = "sol";
      text = "pragma solidity ^0.8.0;\ncontract C {}";
      server = "solidity_ls_nomicfoundation";
      diag = false;
    }
    # marksman runs on the repacked, ICU-free dotnet runtime.
    {
      ext = "md";
      text = "# a heading";
      server = "marksman";
      diag = false;
    }
    # harper-ls is the single binary copied out of the harper package.
    {
      ext = "md";
      text = "# a heading";
      server = "harper_ls";
      diag = false;
    }
    # lua_ls runs with its addon/zh-cn metas pruned (see overlays/slim.nix).
    {
      ext = "lua";
      text = "local x = 1";
      server = "lua_ls";
      diag = false;
    }
  ];

  # Announce every attach; once the expected server arrives, either quit
  # (attach-only) or poll until it publishes a diagnostic. Time out loudly
  # (cq) rather than hang the build.
  attachLua =
    { server, diag, ... }:
    "vim.api.nvim_create_autocmd('LspAttach',{callback=function(a)"
    + " local c=vim.lsp.get_client_by_id(a.data.client_id)"
    + " io.write('ATTACHED: '..c.name..'\\n')"
    + " if c.name=='${server}' then"
    + (
      if diag then
        " local t=vim.uv.new_timer() t:start(2000,2000,vim.schedule_wrap(function()"
        + " if #vim.diagnostic.get(a.buf)>0 then io.write('DIAGNOSED: ${server}\\n') t:stop() vim.cmd('qa!') end end))"
      else
        " vim.schedule(function() vim.cmd('qa!') end)"
    )
    + " end end}); vim.defer_fn(function() io.write('no attach\\n') vim.cmd('cq') end, 240000)";
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

        # Booting also opens :help and parses it: the repacked neovim (see
        # overlays/slim.nix) drops its bundled parsers, so vimdoc must
        # resolve from the curated nvim-treesitter grammars in every variant.
        # The query lookup is the second half of that: nixpkgs ships parsers
        # and queries as separate plugins, and a parser without its queries
        # attaches to the buffer and highlights nothing at all.
        ${lib.concatMapStringsSep "\n"
          (bin: ''
            ${bin} --headless \
              "+lua local ok,err=pcall(function() vim.cmd('help api') vim.treesitter.get_parser(0):parse() assert(vim.treesitter.query.get('vimdoc','highlights'), 'no vimdoc highlights query') end) io.write(ok and 'HELP-TS-OK\n' or 'HELP-TS-FAIL: '..tostring(err)..'\n') vim.cmd('qa!')" \
              2>&1 | grep -a HELP-TS-OK \
              || { echo "${bin}: :help did not parse"; exit 1; }
          '')
          [
            (lib.getExe' lazyvim "lazyvim")
            (lib.getExe' lazyvim-light "lazyvim-light")
          ]
        }

        ${lib.concatMapStringsSep "\n" (
          t:
          let
            want = if t.diag then "DIAGNOSED" else "ATTACHED";
          in
          ''
            printf '%s\n' ${lib.escapeShellArg t.text} > "$TMPDIR/attach.${t.ext}"
            ${lib.getExe' lazyvim "lazyvim"} --headless \
              ${lib.escapeShellArg "+lua ${attachLua t}"} \
              "+edit $TMPDIR/attach.${t.ext}" 2>&1 | grep -a "${want}: ${t.server}" \
              || { echo "${t.server}: no '${want}' for attach.${t.ext}"; exit 1; }
          ''
        ) attach}

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

    touch $out
  ''
