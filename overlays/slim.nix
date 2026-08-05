# Strip packages to what's required at runtime to reduce disk space (without
# rebuilding the world).
final: prev: {
  # Several of node's C dependencies have no dev output: headers, cmake
  # exports and pkg-config files ride in the runtime output (uvwasi's .pc
  # even pins libuv's -dev headers). node links the libraries, never the
  # headers. Same name → same store path length, so the copies can
  # replace the originals byte-for-byte inside node's ELF below.
  withoutHeaders =
    pkg:
    prev.runCommand pkg.name { } ''
      cp -a ${pkg} $out
      chmod -R u+w $out
      rm -rf $out/include $out/lib/pkgconfig $out/lib/cmake
    '';

  # node compiles its build configuration into the binary (process.config),
  # which pins the -dev output of every build dependency — headers and
  # static libs only `node-gyp rebuild` would ever read, ~24M of closure,
  # and projects that compile addons bring their own toolchain anyway.
  # remove-references-to swaps each hash for an invalid one of the same
  # length, so patching the ELF in place is safe; no rebuild of node.
  nodejs-slim-runtime =
    let
      # Dev-splitless runtime deps whose headers only addon builds would
      # read; a version mismatch with node's actual link just makes the
      # swap a no-op, so this list can trail nixpkgs safely.
      headerlessSwaps =
        map
          (p: {
            from = p;
            to = final.withoutHeaders p;
          })
          [
            prev.uvwasi
            prev.simdjson
            prev.simdutf
            prev.ada
          ];
    in
    prev.runCommand prev.nodejs-slim.name
      {
        nativeBuildInputs = [ prev.removeReferencesTo ];
        closure = prev.closureInfo { rootPaths = [ prev.nodejs-slim ]; };
        # vtsls' buildNpmPackage reads meta.platforms from the node it gets.
        inherit (prev.nodejs-slim) meta;
      }
      ''
        cp -a ${prev.nodejs-slim} $out
        chmod -R u+w $out
        # Addon-build material node-gyp would read; node-gyp isn't shipped.
        rm -rf $out/include
        grep -e '-dev$' "$closure/store-paths" | while IFS= read -r p; do
          find $out -type f -exec remove-references-to -t "$p" {} +
        done
        # node's own prefix, recorded in the binary's process.config, would
        # chain the copy to the original store path and everything it pins.
        find $out -type f -exec remove-references-to -t ${prev.nodejs-slim} {} +
        # Equal-length swaps (see withoutHeaders), safe in the ELF's rpath.
        ${prev.lib.concatMapStringsSep "\n" (
          s: ''find $out -type f -exec sed -i "s|${s.from}|${s.to}|g" {} +''
        ) headerlessSwaps}
      '';

  # python3 ships its own embedding toolchain in the runtime output:
  # libpython.a plus build config (60M), IDLE (6M) and the test suite —
  # compile-time material for an interpreter that rides cli.nix onto
  # every host and under three package envs. ensurepip stays so
  # `python -m venv` keeps seeding pip. Equal-length self-rewrite keeps
  # the copy off the original's closure (paths inside .pyc are
  # length-prefixed strings, so the swap is byte-exact there too).
  python3-runtime = prev.runCommand prev.python3.name { inherit (prev.python3) meta; } ''
    cp -a ${prev.python3} $out
    chmod -R u+w $out
    rm -rf $out/lib/python*/config-* $out/lib/python*/idlelib \
      $out/lib/python*/test $out/bin/idle*
    find $out -type f -exec sed -i "s|${prev.python3}|$out|g" {} +
  '';

  # Rewrites a python application's whole closure onto python3-runtime:
  # replaceDependency nar-copies each dependent path with the store path
  # swapped (same name → equal length), no rebuilds.
  withPython3Runtime =
    drv:
    prev.replaceDependency {
      inherit drv;
      oldDependency = prev.python3;
      newDependency = final.python3-runtime;
    };

  # node-gyp is a build tool, but packages ship it anyway and its residue
  # retains build inputs at runtime: config.gypi records store paths (the
  # npm-deps fixed-output derivation among them), and its own python
  # scripts get store-python shebangs at fixup — an interpreter in the
  # closure for scripts nothing runs.
  withoutNpmBuildResidue =
    drv:
    drv.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        find "$out" -name config.gypi -delete
        find "$out" -type d -name node-gyp -prune -exec rm -rf {} +
        # Native modules' build trees: only the compiled Release/*.node is
        # runtime; Makefiles and .deps depfiles record compiler and include
        # store paths (glib-dev, and with it python, in keytar's case).
        find "$out" -type d \( -name .deps -o -name obj.target \) -prune -exec rm -rf {} +
        find "$out" -path "*/build/*" \( -name "*.mk" -o -name Makefile \) -delete
        # Vendored dev scripts (katex ships its font-generation tooling):
        # fixup patches their shebangs, putting a python in the closure for
        # scripts no node package ever executes.
        find "$out" -path "*/node_modules/*" -name "*.py" -delete
        # The pruned trees leave .bin/node-gyp symlinks dangling, which
        # noBrokenSymlinks rightly rejects.
        find "$out" -xtype l -delete
      '';
      # buildNpmPackage shebangs its outputs with the full `nodejs` — the
      # slim+npm+corepack symlink join — though at runtime they only exec
      # `node`. Re-point everything at the runtime node, dropping npm,
      # corepack and node's own -dev pins from the closure. postFixup, not
      # postInstall: patchShebangs writes these references during fixup.
      # Bundled JS can carry NUL bytes, so no `grep -I`: skip only real
      # ELF objects, where a different-length path would corrupt offsets.
      postFixup = (old.postFixup or "") + ''
        for nodePath in ${prev.nodejs} ${prev.nodejs-slim}; do
          { grep -rlZ "$nodePath" "$out" || true; } | while IFS= read -r -d ''' f; do
            case "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" in
              7f454c46 | feedfacf | cffaedfe | cafebabe | bebafeca) continue ;;
            esac
            sed -i "s|$nodePath|${final.nodejs-slim-runtime}|g" "$f"
          done
        done
      '';
    });

  # dist/ is a self-contained webpack bundle — typeshed and a vendored
  # vscode-languageserver ride inside it — while node_modules is 217M of
  # pyright's monorepo tooling (@azure, prettier, npm-check-updates)
  # nothing loads; it also leaked npm-deps through keytar's config.gypi.
  # The .maps only ever served the upstream debugger.
  basedpyright = final.withoutNpmBuildResidue (
    prev.basedpyright.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        rm -rf $out/lib/node_modules/pyright-root/node_modules
        rm -f $out/lib/node_modules/pyright-root/dist/*.map
      '';
    })
  );

  # Repack of the cached build. The service is built (packages/service/
  # dist) from a vendored vscode source checkout that remains in the
  # output — 144M no code path reads again — alongside the pnpm store
  # entries of its build toolchain. The typescript package stays: the
  # service spawns tsserver from it. The cached build runs on
  # nodejs-slim_22; its scripts are text, so re-pointing them at the
  # runtime node keeps one node in the closure (attach + diagnostics
  # verified by the variants check).
  vtsls = prev.runCommand prev.vtsls.name { inherit (prev.vtsls) meta; } ''
    cp -a ${prev.vtsls} $out
    chmod -R u+w $out
    root=$out/lib/vtsls-language-server
    rm -rf "$root"/packages/service/{vscode,src,patches}
    for dev in \
      "esbuild@" "@esbuild+" "eslint@" "@eslint+" "@eslint-community+" \
      "@typescript-eslint+" "typescript-eslint@" "rollup@" "@rollup+" \
      "vite@" "vitest@" "@vitest+" "@types+" "lint-staged@" \
      "simple-git-hooks@" "prettier@" "husky@"; do
      rm -rf "$root"/node_modules/.pnpm/"$dev"*
    done
    find $out -xtype l -delete
    find $out -type f -exec sed -i \
      -e "s|${prev.vtsls}|$out|g" \
      -e "s|${prev.nodejs-slim_22}|${final.nodejs-slim-runtime}|g" {} +
  '';

  # Repack of the cached build. prettierd declares only core_d and
  # prettier; typescript (23M), babel and friends are devDependencies the
  # vendored install unpacked anyway — prettier brings its own typescript
  # parser. Its scripts are shebanged with the full nodejs join, though
  # at runtime they only exec `node`.
  prettierd =
    prev.runCommand prev.prettierd.name
      {
        nativeBuildInputs = [ prev.nodejs-slim ];
        inherit (prev.prettierd) meta;
      }
      ''
        cp -a ${prev.prettierd} $out
        chmod -R u+w $out
        node ${./prune-node-modules.js} $out/lib/node_modules/@fsouza/prettierd
        find $out -name config.gypi -delete
        find $out -xtype l -delete
        find $out -type f -exec sed -i \
          -e "s|${prev.prettierd}|$out|g" \
          -e "s|${prev.nodejs}|${final.nodejs-slim-runtime}|g" {} +
      '';

  # Repack of the cached build. Only jsonls is wired up (checked by the
  # variants attach test): the css, html and eslint servers go, along
  # with the 17M typescript copy that only they load — the json server's
  # dist is self-contained. Its entry points are makeBinaryWrapper ELFs
  # that exec nodejs-slim by absolute path; same package name → same
  # store path length, so the sed is byte-exact even there.
  vscode-langservers-extracted =
    prev.runCommand prev.vscode-langservers-extracted.name
      { inherit (prev.vscode-langservers-extracted) meta; }
      ''
        cp -a ${prev.vscode-langservers-extracted} $out
        chmod -R u+w $out
        rm -rf $out/lib/extensions/node_modules \
          $out/lib/extensions/css-language-features \
          $out/lib/extensions/html-language-features \
          $out/lib/extensions/eslint-language-features \
          $out/bin/vscode-css-language-server \
          $out/bin/vscode-html-language-server \
          $out/bin/vscode-eslint-language-server
        find $out -type f -exec sed -i \
          -e "s|${prev.vscode-langservers-extracted}|$out|g" \
          -e "s|${prev.nodejs-slim}|${final.nodejs-slim-runtime}|g" {} +
      '';

  # Repack of the cached build. lua_ls serves nvim configs here: the
  # bundled third-party addon definitions and the zh-cn metas and
  # messages never load.
  lua-language-server =
    prev.runCommand prev.lua-language-server.name { inherit (prev.lua-language-server) meta; }
      ''
        cp -a ${prev.lua-language-server} $out
        chmod -R u+w $out
        rm -rf $out/share/lua-language-server/meta/3rd
        find "$out/share/lua-language-server" -depth -name '*zh-cn*' -exec rm -rf {} +
        find $out -type f -exec sed -i "s|${prev.lua-language-server}|$out|g" {} +
      '';

  # nvim links libtree-sitter out of a package that is 97% CLI: 11M of
  # `tree-sitter` generate/test tooling against 260K of library.
  tree-sitter-runtime = prev.runCommand prev.tree-sitter.name { } ''
    cp -a ${prev.tree-sitter} $out
    chmod -R u+w $out
    rm -rf $out/bin $out/include $out/share $out/config.schema.json $out/lib/pkgconfig
  '';

  # A repack of neovim, not a rebuild: swap the tree-sitter package for
  # the library-only copy (same name → equal length, safe inside the
  # ELF), drop message translations, and drop the bundled parsers — the
  # curated nvim-treesitter grammars ship the same seven in every
  # variant, with queries matching their versions. The variants check
  # opens :help and parses it to prove vimdoc still resolves.
  neovim-unwrapped-runtime =
    prev.runCommand prev.neovim-unwrapped.name
      {
        inherit (prev.neovim-unwrapped) meta version;
        # nixCats builds the wrapper's lua env out of this passthru.
        passthru = {
          inherit (prev.neovim-unwrapped) lua;
        };
      }
      ''
        cp -a ${prev.neovim-unwrapped} $out
        chmod -R u+w $out
        rm -rf $out/share/locale $out/lib/nvim/parser
        # nvim embeds its own prefix (the default VIMRUNTIME); left alone
        # it chains the copy to the original and everything it references.
        find $out -type f -exec sed -i \
          -e "s|${prev.neovim-unwrapped}|$out|g" \
          -e "s|${prev.tree-sitter}|${final.tree-sitter-runtime}|g" {} +
      '';

  # The MANPAGER/EDITOR nvim: the runtime repack shared with lazyvim,
  # plus the seven bundled parsers stock ftplugins assert at load (help,
  # lua, markdown, query auto-start treesitter in 0.12) — real copies of
  # dependency-free .so files, so the original nvim and its full
  # tree-sitter link stay out of the closure. ~3M over the shared repack
  # against the ~180M `pkgs.neovim` wrapper (second nvim, full
  # tree-sitter, xdg-utils→perl).
  neovim-bare =
    prev.runCommand "${prev.neovim-unwrapped.name}-bare"
      {
        nativeBuildInputs = [ prev.makeWrapper ];
        inherit (prev.neovim-unwrapped) meta;
      }
      ''
        install -Dm444 -t $out/rtp/parser ${prev.neovim-unwrapped}/lib/nvim/parser/*.so
        makeWrapper ${final.neovim-unwrapped-runtime}/bin/nvim $out/bin/nvim \
          --add-flags "--cmd 'set rtp^=$out/rtp'"
      '';

  # The editor only runs the language server (lua/plugins/harper.lua);
  # harper-cli is a second 55M copy of the same embedded dictionaries. A
  # real copy, not a symlink: linking would keep the whole original in
  # the closure.
  harper = prev.runCommand prev.harper.name { inherit (prev.harper) meta; } ''
    install -Dm755 ${prev.harper}/bin/harper-ls $out/bin/harper-ls
  '';

  # NOTE: pandoc's stock binary carries 59M of dynamic symbol tables
  # (--export-dynamic roots all ~450k Haskell symbols) and a relink with
  # -optl-Wl,--no-export-dynamic more than halves it, 209M → 95M — but
  # that means compiling pandoc-cli on every nixpkgs bump, so the cached
  # binary ships as-is. Revisit if a substituter ever fronts these hosts.

  # marksman is the only dotnet consumer in the editor closure, and dotnet
  # only touches ICU through libSystem.Globalization.Native — 39M of
  # locale tables a markdown server has no use for. With invariant
  # globalization that library never dlopens ICU, so the rpath entries
  # remove-references-to invalidates are dead. The scrubbed runtime rides
  # inside the package (discovered from the original wrapper rather than
  # named, so a marksman bump can't pair it with the wrong runtime) and
  # the original chain — wrapped runtime → runtime → icu — drops out of
  # the closure entirely. Linux-only: patchelf cannot edit Mach-O, and on
  # darwin dotnet uses the system ICU anyway, so there is nothing to trim.
  marksman =
    if !prev.stdenv.hostPlatform.isLinux then
      prev.marksman
    else
      prev.runCommand prev.marksman.name
        {
          nativeBuildInputs = [
            prev.removeReferencesTo
            prev.patchelf
          ];
          closure = prev.closureInfo { rootPaths = [ prev.marksman ]; };
          inherit (prev.marksman) meta;
        }
        ''
          cp -a ${prev.marksman} $out
          chmod -R u+w $out

          droot=$(sed -n "s|^export DOTNET_ROOT='\([^']*\)'$|\1|p" $out/bin/marksman)
          host=$(readlink -f "$droot/dotnet")
          runtime=''${host%/share/dotnet/dotnet}
          cp -a "$runtime" $out/dotnet-runtime
          chmod -R u+w $out/dotnet-runtime
          # buildDotnetModule patches the ICU sonames into the apphost's
          # DT_NEEDED so managed dlopen resolves them; it imports no ICU
          # symbols (checked with nm -D), so dropping the entries is safe
          # even under BIND_NOW. The rpaths in the apphost and the
          # runtime's globalization libs go the same way.
          # Kerberos rides the same overlinking (dotnet's System.Net
          # negotiate auth, no imported symbols either).
          patchelf --remove-needed libicui18n.so --remove-needed libicuuc.so \
            --remove-needed libgssapi_krb5.so \
            $out/lib/marksman/marksman
          grep -e '-icu4c-' -e '-krb5-' "$closure/store-paths" | while IFS= read -r p; do
            find $out -type f -exec remove-references-to -t "$p" {} +
          done

          cat > $out/bin/marksman <<EOF
          #!${prev.runtimeShell} -e
          export DOTNET_ROOT="$out/dotnet-runtime/share/dotnet"
          export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
          exec "$out/lib/marksman/marksman" "\$@"
          EOF
          chmod +x $out/bin/marksman
        '';

  # A repack of the cached gitMinimal, not a rebuild (its install checks
  # alone run a 29k-test suite). Plugins only run plumbing and porcelain:
  # `contrib` (which pins bash-interactive through its patched shebangs),
  # message catalogs, and the server/exotic-transport surface — scalar,
  # the legacy dumb-http client, imap-send, the login shell — all go.
  # Scrubbing gettext is safe on a live NLS build: git-sh-i18n probes
  # gettext.sh with `type`, and the invalidated path falls through to the
  # built-in scheme. sh-i18n--envsubst stays: that fallback still uses it
  # to interpolate script messages (submodule et al.).
  gitMinimal-runtime =
    prev.runCommand prev.gitMinimal.name
      {
        nativeBuildInputs = [ prev.removeReferencesTo ];
        inherit (prev.gitMinimal) meta;
      }
      ''
        cp -a ${prev.gitMinimal} $out
        chmod -R u+w $out
        rm -rf $out/share/git/contrib $out/share/locale
        rm -f $out/bin/scalar $out/bin/git-shell $out/bin/git-cvsserver \
          $out/libexec/git-core/scalar \
          $out/libexec/git-core/git-shell \
          $out/libexec/git-core/git-imap-send \
          $out/libexec/git-core/git-http-push \
          $out/libexec/git-core/git-http-fetch \
          $out/libexec/git-core/git-cvsserver
        find $out -xtype l -delete
        # git embeds its own prefix; equal-length rewrite keeps the copy
        # self-contained instead of chained to the original.
        find $out -type f -exec sed -i "s|${prev.gitMinimal}|$out|g" {} +
        find $out -type f -exec remove-references-to -t ${prev.gettext} {} +
      '';

  # rga shells out to ffmpeg for media adapters (subtitles, metadata);
  # the default ffmpeg build carries gtk3/gtk4, sdl2, x265, flite and
  # friends — ~1G of desktop and encoder closure for a tool that only
  # ever decodes. ffmpeg-headless keeps the decoders and ffprobe.
  ripgrep-all = prev.ripgrep-all.override { ffmpeg = prev.ffmpeg-headless; };

  # The MCP server only ever drives chromium (its wrapper hard-sets
  # PLAYWRIGHT_BROWSERS_PATH), yet it retains firefox, webkit and the
  # chromium headless shell — ~670M of browsers no code path launches —
  # through two references to the full browser farm: its own wrapper, and
  # the bin/playwright wrapper inside the playwright-test package it
  # symlinks its node modules from. Headless launches fall back to the
  # full chromium binary when the shell is absent (verified end-to-end:
  # MCP navigate over stdio with --headless). Both farms are linkFarm
  # "playwright-browsers" — equal length, safe to swap in the text
  # wrapper.
  playwright-mcp =
    let
      inherit (prev.playwright-driver.passthru) browsers browsers-chromium;
      playwright-test-chromium =
        prev.runCommand prev.playwright-test.name { inherit (prev.playwright-test) meta; }
          ''
            cp -a ${prev.playwright-test} $out
            chmod -R u+w $out
            # bin/playwright embeds the original's prefix (NODE_PATH,
            # --add-flags); left alone it chains the copy to the original
            # and the full farm it pins.
            find $out -type f -exec sed -i \
              -e "s|${prev.playwright-test}|$out|g" \
              -e "s|${browsers}|${browsers-chromium}|g" {} +
          '';
    in
    prev.playwright-mcp.override {
      playwright-test = playwright-test-chromium;
      playwright-driver = prev.playwright-driver.overrideAttrs (old: {
        passthru = old.passthru // {
          browsers = browsers-chromium;
        };
      });
    };
}
