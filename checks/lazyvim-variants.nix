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
#
# Store paths being present is the weaker half. The editor has broken with
# every path in place — grammars shipped without their queries, a server whose
# `root_dir` threw before it could attach — so ./lazyvim-probe.lua asserts the
# rest from inside a running editor, once per variant.

let
  fullClosure = closureInfo { rootPaths = [ lazyvim ]; };
  lightClosure = closureInfo { rootPaths = [ lazyvim-light ]; };

  # `curatedGrammars` in packages/lazyvim/plugins.nix: what `general` ships, so
  # what both variants must have.
  curatedGrammars = [
    "bash"
    "c"
    "diff"
    "fish"
    "json"
    "lua"
    "luadoc"
    "luap"
    "markdown"
    "markdown_inline"
    "nix"
    "printf"
    "python"
    "query"
    "regex"
    "toml"
    "vim"
    "vimdoc"
    "xml"
    "yaml"
  ];

  # Only `treesitterAll` carries these, so they double as the light/full split.
  extraGrammars = [
    "beancount"
    "go"
    "rust"
    "typescript"
  ];

  # Written to `sample.<ext>` and opened: filetype detection runs off the
  # extension and the treesitter language off the filetype (sh → bash,
  # rs → rust), so this walks the same resolution an opened file does — which
  # is why the extension, not the language, names the file. Snippets are short
  # enough to stay obvious and long enough to carry a highlight; a grammar
  # missing its queries yields captures for none of them.
  samples = lang: ext: text: { inherit lang ext text; };

  curatedSamples = [
    (samples "bash" "sh" ''echo "hi"'')
    (samples "json" "json" ''{ "a": 1 }'')
    (samples "lua" "lua" "local x = 1")
    (samples "markdown" "md" "# hi")
    (samples "nix" "nix" "{ foo = 1; }")
    (samples "python" "py" "import os")
    (samples "toml" "toml" "a = 1")
    (samples "vim" "vim" "set number")
    (samples "xml" "xml" "<a>b</a>")
    (samples "yaml" "yaml" "a: 1")
  ];

  extraSamples = [
    (samples "beancount" "beancount" "2024-01-02 * \"Store\" \"Thing\"\n  Assets:Cash  -10.00 USD")
    (samples "go" "go" "package main\n\nfunc main() {}")
    (samples "rust" "rs" "fn main() {}")
    (samples "typescript" "ts" "const a: number = 1;")
  ];

  # Formatter, input and the exact output the shipped binary produces. LazyVim
  # configures a superset of what the editor ships and conform skips the rest
  # in silence, so only the result tells the two apart. `nixfmt` rides the
  # `nix` category; `stylua`, `shfmt` and conform's own `trim_whitespace` are
  # in `general`, so they must work in both variants.
  generalFormats = [
    {
      ext = "lua";
      input = "local  x   =  1\n";
      want = "local x = 1";
    }
    {
      ext = "sh";
      input = "if true; then\necho hi\nfi\n";
      want = "if true; then\n  echo hi\nfi";
    }
    {
      ext = "md";
      input = "# hi\n\ntrailing   \n";
      want = "# hi\n\ntrailing";
    }
  ];
  nixFormat = {
    ext = "nix";
    input = "{foo=1;}\n";
    want = "{ foo = 1; }";
  };

  # A word each dictionary knows and one no dictionary does, so a spellfile
  # that is on the runtimepath but never read is still a failure.
  spells = [
    {
      lang = "it";
      known = "gatto";
      unknown = "qwertyuiop";
    }
    {
      lang = "es";
      known = "gato";
      unknown = "qwertyuiop";
    }
  ];

  probe = ./lazyvim-probe.lua;

  # One invocation per variant. The probe reports through its output and the
  # shell gates on that: nvim's own exit status is not a signal here, since an
  # LSP client that fails to shut down cleanly makes it non-zero after a run
  # that asserted everything it was asked to. Redirecting rather than piping
  # keeps stdenv's `pipefail` from turning that into a silent abort.
  #
  # The traceback grep is not redundant with the probe's own :messages check:
  # an error thrown out of an autocmd headless goes straight to stderr and
  # never reaches the message history, so only the log sees it.
  #
  # `-n` and a scratch directory per variant: the two runs share a state
  # directory, so a swap file left behind by one turns the next one's buffers
  # read-only (E325) over the same paths — a failure about nothing.
  probeRun =
    {
      name,
      bin,
      spec,
    }:
    ''
      echo "PROBE-START ${bin}"
      rm -rf "$TMPDIR/probe-${name}" && mkdir -p "$TMPDIR/probe-${name}"
      PROBE_DIR="$TMPDIR/probe-${name}" PROBE_SPEC=${lib.escapeShellArg (builtins.toJSON spec)} \
        ${bin} -n --headless "+luafile ${probe}" > "$TMPDIR/probe-${name}.log" 2>&1 || true
      cat "$TMPDIR/probe-${name}.log"
      grep -aq PROBE-OK "$TMPDIR/probe-${name}.log" \
        || { echo "${bin}: in-editor probe failed"; exit 1; }
      if grep -aq -e "stack traceback" -e "Error executing" "$TMPDIR/probe-${name}.log"; then
        echo "${bin}: lua error while probing"; exit 1
      fi
    '';

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
        # (That the query behind it resolves too is ./lazyvim-probe.lua's job,
        # for vimdoc and every other grammar.)
        ${lib.concatMapStringsSep "\n"
          (bin: ''
            ${bin} --headless \
              "+lua local ok,err=pcall(function() vim.cmd('help api') vim.treesitter.get_parser(0):parse() end) io.write(ok and 'HELP-TS-OK\n' or 'HELP-TS-FAIL: '..tostring(err)..'\n') vim.cmd('qa!')" \
              2>&1 | grep -a HELP-TS-OK \
              || { echo "${bin}: :help did not parse"; exit 1; }
          '')
          [
            (lib.getExe' lazyvim "lazyvim")
            (lib.getExe' lazyvim-light "lazyvim-light")
          ]
        }

        # A server can attach and still leave the buffer broken: LazyVim's go
        # extra once threw out of `LspAttach` reading capabilities blink.cmp
        # had not registered yet. So the run must also come back clean — a
        # traceback here is a plugin crashing, not a tool that is missing
        # (nvim-lint says "Error running forge" and that is expected).
        ${lib.concatMapStringsSep "\n" (
          t:
          let
            want = if t.diag then "DIAGNOSED" else "ATTACHED";
          in
          ''
            printf '%s\n' ${lib.escapeShellArg t.text} > "$TMPDIR/attach.${t.ext}"
            ${lib.getExe' lazyvim "lazyvim"} -n --headless \
              ${lib.escapeShellArg "+lua ${attachLua t}"} \
              "+edit $TMPDIR/attach.${t.ext}" > "$TMPDIR/attach.log" 2>&1 || true
            cat "$TMPDIR/attach.log"
            grep -aq "${want}: ${t.server}" "$TMPDIR/attach.log" \
              || { echo "${t.server}: no '${want}' for attach.${t.ext}"; exit 1; }
            if grep -aq -e "stack traceback" -e "Error executing" "$TMPDIR/attach.log"; then
              echo "${t.server}: lua error while attaching to attach.${t.ext}"; exit 1
            fi
          ''
        ) attach}

        # What the store paths cannot show: grammars that actually paint,
        # formatters that actually run, spellfiles nvim actually reads.
        ${probeRun {
          name = "full";
          bin = lib.getExe' lazyvim "lazyvim";
          spec = {
            min_grammars = 300;
            present_grammars = curatedGrammars ++ extraGrammars;
            # The `treesitterAll` denylist, asserted from the other side.
            absent_grammars = [
              "systemverilog"
              "gnuplot"
              "razor"
              "fortran"
              "fsharp"
              "slang"
            ];
            samples = curatedSamples ++ extraSamples;
            formats = generalFormats ++ [ nixFormat ];
            inherit spells;
          };
        }}

        ${probeRun {
          name = "light";
          bin = lib.getExe' lazyvim-light "lazyvim-light";
          spec = {
            # The curated set and nothing else: the light build must not
            # quietly regain the full grammar set, nor the tooling behind it.
            min_grammars = 20;
            present_grammars = curatedGrammars;
            absent_grammars = extraGrammars;
            samples = curatedSamples;
            formats = generalFormats;
            inherit spells;
          };
        }}

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
