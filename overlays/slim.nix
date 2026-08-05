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
            [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] && continue
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

  # The service is built (packages/service/dist) from a vendored vscode
  # source checkout that remains in the output — 144M no code path reads
  # again — alongside the pnpm store entries of its build toolchain. The
  # typescript package stays: the service spawns tsserver from it.
  vtsls = final.withoutNpmBuildResidue (
    (prev.vtsls.override { nodejs-slim_22 = prev.nodejs-slim; }).overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        root=$out/lib/vtsls-language-server
        rm -rf "$root"/packages/service/{vscode,src,patches}
        for dev in \
          "esbuild@" "@esbuild+" "eslint@" "@eslint+" "@eslint-community+" \
          "@typescript-eslint+" "typescript-eslint@" "rollup@" "@rollup+" \
          "vite@" "vitest@" "@vitest+" "@types+" "lint-staged@" \
          "simple-git-hooks@" "prettier@" "husky@"; do
          rm -rf "$root"/node_modules/.pnpm/"$dev"*
        done
      '';
    })
  );

  # Only lazyvim ships these; both wrap their entry points with the full
  # nodejs join, which withoutNpmBuildResidue re-points at the runtime node.
  # prettierd declares only core_d and prettier; typescript (23M), babel
  # and friends are devDependencies the vendored install unpacked anyway —
  # prettier brings its own typescript parser.
  prettierd = final.withoutNpmBuildResidue (
    prev.prettierd.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        node ${./prune-node-modules.js} $out/lib/node_modules/@fsouza/prettierd
      '';
    })
  );
  # Its entry points are makeBinaryWrapper ELFs that exec nodejs-slim, so
  # the node has to be swapped at build time; sed can't touch them.
  vscode-langservers-extracted = final.withoutNpmBuildResidue (
    prev.vscode-langservers-extracted.override { nodejs-slim = final.nodejs-slim-runtime; }
  );

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

  # The editor only runs the language server (lua/plugins/harper.lua);
  # harper-cli is a second 55M copy of the same embedded dictionaries. A
  # real copy, not a symlink: linking would keep the whole original in
  # the closure.
  harper = prev.runCommand prev.harper.name { inherit (prev.harper) meta; } ''
    install -Dm755 ${prev.harper}/bin/harper-ls $out/bin/harper-ls
  '';

  # The stock binary is linked with --export-dynamic, which keeps all
  # ~450k Haskell symbols in the dynamic table (59M of .dynsym/.dynstr)
  # and roots them against --gc-sections, so dead code stays too.
  # Relinking without it more than halves the binary (209M → 95M); only
  # the pandoc-cli executable rebuilds, the pandoc library stays cached.
  # Lua filters keep working: they call registered functions, not dlsym
  # (verified: md→html tables, --lua-filter, gfm→latex).
  pandoc = prev.pandoc.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--ghc-options=-optl-Wl,--no-export-dynamic"
    ];
  });

  # marksman is the only dotnet consumer in the editor closure, and dotnet
  # only touches ICU through libSystem.Globalization.Native — 39M of
  # locale tables a markdown server has no use for. With invariant
  # globalization that library never dlopens ICU, so the rpath entries
  # remove-references-to invalidates are dead. The scrubbed runtime rides
  # inside the package (discovered from the original wrapper rather than
  # named, so a marksman bump can't pair it with the wrong runtime) and
  # the original chain — wrapped runtime → runtime → icu — drops out of
  # the closure entirely.
  marksman =
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
        patchelf --remove-needed libicui18n.so --remove-needed libicuuc.so \
          $out/lib/marksman/marksman
        grep -e '-icu4c-' "$closure/store-paths" | while IFS= read -r p; do
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

  # lazygit and the git plugins only run plumbing, so drop the translation
  # machinery. NO_GETTEXT alone is not enough: nixpkgs' git-sh-i18n patch
  # hardcodes the gettext store path into a branch NO_GETTEXT makes dead,
  # and `contrib` — which nothing on any code path reaches — retains
  # bash-interactive through its patched shebangs. ~32M off every variant.
  gitMinimal-runtime = (prev.gitMinimal.override { nlsSupport = false; }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -rf $out/share/git/contrib
      find $out -xtype l -delete
      sed -i -e 's|${prev.gettext}|/gettext-elided-see-slim-overlay|g' \
        $out/libexec/git-core/git-sh-i18n
    '';
  });
}
