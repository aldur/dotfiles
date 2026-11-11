# Strip packages to what's required at runtime to reduce disk space (without
# rebuilding the world).
{ self }:
final: prev:
let
  runtimeLibraries = import ./runtime-libraries.nix { pkgs = prev; };

  # node-gyp is a build tool, but packages ship it anyway and its residue
  # retains build inputs at runtime: config.gypi records store paths (the
  # npm-deps fixed-output derivation among them), and its own python
  # scripts get store-python shebangs at fixup — an interpreter in the
  # closure for scripts nothing runs. Operates on $out; shared by the
  # build hooks (withoutNpmBuildResidue) and the runCommand repacks.
  npmResidueSweep = ''
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
  # corepack and node's own -dev pins from the closure. Bundled JS can
  # carry NUL bytes, so no `grep -I`: skip only real ELF/Mach-O objects,
  # where a different-length path would corrupt offsets.
  nodeJoinRepoint = ''
    for nodePath in ${prev.nodejs} ${prev.nodejs-slim}; do
      { grep -rlZ "$nodePath" "$out" || true; } | while IFS= read -r -d ''' f; do
        case "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" in
          7f454c46 | feedfacf | cffaedfe | cafebabe | bebafeca) continue ;;
        esac
        sed -i "s|$nodePath|${final.nodejs-slim-runtime}|g" "$f"
      done
    done
  '';

  # remarks' pymupdf drags the full-language tesseract wrapper — 1G of
  # OCR models — through the mupdf variant it links. Reconstructing that
  # variant the way python-modules/pymupdf does lets both be repacked as
  # same-name copies (equal store path length, byte-exact swaps), never
  # rebuilt. If the reconstruction drifts from what pymupdf actually
  # linked, the positive asserts below fail the build instead of letting
  # the tessdata silently return; checks/slim-closures.nix guards the
  # closure end, too.
  mupdfOcr = prev.lib.getLib (
    prev.mupdf.override {
      enableOcr = true;
      enableCxx = true;
      enablePython = true;
      enableBarcode = true;
      inherit (prev) python3;
    }
  );
  mupdfLite = prev.runCommand mupdfOcr.name { } ''
    cp -a ${mupdfOcr} $out
    chmod -R u+w $out
    find $out -type f -exec sed -i \
      -e "s|${mupdfOcr}|$out|g" \
      -e "s|${prev.tesseract}|${final.tesseract-lite}|g" {} +
    grep -rq ${final.tesseract-lite} $out
    ! grep -rq ${prev.tesseract} $out
  '';
  pythonForRemarks = prev.python3.override {
    packageOverrides = pyself: pysuper: {
      pymupdf = pyself.toPythonModule (
        prev.runCommand pysuper.pymupdf.name
          {
            # Python envs are assembled from eval-level propagation, and
            # the raw copy would lose it: re-propagate the original
            # inputs with the OCR mupdf swapped for the lite repack (it
            # provides the `mupdf` bindings module).
            propagatedBuildInputs = map (
              d: if (d.outPath or null) == mupdfOcr.outPath then pyself.toPythonModule mupdfLite else d
            ) pysuper.pymupdf.propagatedBuildInputs;
          }
          ''
            cp -a ${pysuper.pymupdf} $out
            chmod -R u+w $out
            find $out -type f -exec sed -i \
              -e "s|${pysuper.pymupdf}|$out|g" \
              -e "s|${mupdfOcr}|${mupdfLite}|g" {} +
            grep -rq ${mupdfLite} $out
            ! grep -rq ${mupdfOcr} $out
          ''
      );
    };
  };
  # Repack of the cached build. pnpm's entry point execs nodejs-slim by
  # absolute path; same name → same store path length. Private: pnpm is
  # also a build tool of other packages, and a new derivation there would
  # rebuild them.
  pnpmRuntime =
    prev.runCommand prev.pnpm.name { inherit (prev.pnpm) meta; } ''
      cp -a ${prev.pnpm} $out
      chmod -R u+w $out
      find $out -type f -exec sed -i \
        -e "s|${prev.pnpm}|$out|g" \
        -e "s|${prev.nodejs-slim}|${final.nodejs-slim-runtime}|g" {} +
      # A no-op swap would silently keep the unstripped node.
      grep -rq ${final.nodejs-slim-runtime} $out
      ! grep -rq ${prev.nodejs-slim} $out
    '';
  # The generic BLAS/LAPACK outputs each copy OpenBLAS twice to change its
  # SONAME. NumPy retains all four copies (including LAPACK through its build
  # metadata), although OpenBLAS already provides every required ABI. Repack
  # the cached NumPy to load OpenBLAS directly: libblas.so.3 is a copy of
  # libopenblas.so.0 with a different SONAME. This saves ~133 MiB without
  # removing numerical code, headers, or configuration metadata.
  numpyForLlm =
    let
      numpy = prev.python3.pkgs.numpy;
      blas = prev.lib.getLib prev.blas;
      openblas = prev.blas.provider;
    in
    prev.python3.pkgs.toPythonModule (
      prev.runCommand numpy.name
        {
          # The stdenv replaces patchelf after the overlays. Only that
          # one is in the binary cache, thus `final`.
          nativeBuildInputs = [ final.patchelf ];
          inherit (numpy) meta propagatedBuildInputs;
          # A leftover would silently keep the copies in the closure.
          disallowedReferences = [
            numpy
            blas
            prev.blas.dev
            (prev.lib.getLib prev.lapack)
            prev.lapack.dev
          ];
        }
        ''
          cp -a ${numpy} $out
          chmod -R u+w $out
          find $out -type f -exec sed -i "s|${numpy}|$out|g" {} +
          sed -i \
            -e "s|${prev.blas.dev}|${openblas.dev}|g" \
            -e "s|${prev.lapack.dev}|${openblas.dev}|g" \
            $out/${prev.python3.sitePackages}/numpy/__config__.py
          # The bytecode of the edited file is stale and keeps the old paths.
          rm $out/${prev.python3.sitePackages}/numpy/__pycache__/__config__.*.pyc
          grep -rlZ ${blas} $out | while IFS= read -r -d ''' f; do
            patchelf --replace-needed libblas.so.3 libopenblas.so.0 \
              --set-rpath "$(patchelf --print-rpath "$f" | sed "s|${blas}|${prev.lib.getLib openblas}|g")" "$f"
          done
        ''
    );

  # Repoint only llm's runtime Python modules at the repacked NumPy (same
  # version/ABI). Overriding the whole Python package set also rebuilds its
  # test-only dependencies, including SciPy and the networking stack.
  # `paths` is the environment's already resolved module closure. Using its
  # dependency metadata avoids replaceDependencies' import-from-derivation,
  # so ARM/Darwin evaluation still works from a Linux host. The direct
  # replacement helper checks equal-length names and rewrites NARs, including
  # symlinks and binary wrappers. Include transitive modules: Python wrappers
  # embed their entire PYTHONPATH, not just immediate dependencies.
  moduleKey = pkg: builtins.unsafeDiscardStringContext pkg.outPath;
  llmRuntimeModules = prev.lib.mapAttrs (
    path: pkg:
    let
      repoint = dep: llmRuntimeModules.${moduleKey dep} or dep;
      replacements = prev.lib.filter (r: r.oldDependency.outPath != r.newDependency.outPath) (
        map (dep: {
          oldDependency = dep;
          newDependency = repoint dep;
        }) (prev.lib.filter (dep: dep.outPath != path) (pkg.requiredPythonModules or [ ]))
      );
    in
    if path == prev.python3.pkgs.numpy.outPath then
      numpyForLlm
    else if replacements == [ ] then
      pkg
    else
      prev.python3.pkgs.toPythonModule (
        (prev.replaceDirectDependencies { drv = pkg; inherit replacements; }).overrideAttrs (_: {
          inherit (pkg) meta;
          propagatedBuildInputs = map repoint (pkg.propagatedBuildInputs or [ ]);
        })
      )
  ) (prev.lib.listToAttrs (map (pkg: prev.lib.nameValuePair (moduleKey pkg) pkg) prev.llmWithPlugins.paths));

  slimmed = {
  # Both tools otherwise retain nixpkgs' older default Nix alongside the
  # latest version installed by modules/nix.nix. Keep comma's patched build
  # and rewrite its embedded executable paths; nix-direnv is just a script.
  # On Darwin, the two tools stay stock and keep the older Nix.
  # nix-index-database calls comma.override to supply its index package.
  comma = prev.lib.makeOverridable (
    { nix ? prev.nixVersions.latest, ... }@args:
    let
      cached = prev.comma.override (builtins.removeAttrs args [ "nix" ]);
    in
    if prev.nix.outPath == nix.outPath then
      cached
    else
      (prev.replaceDirectDependencies {
        drv = cached;
        replacements = [
          {
            oldDependency = prev.nix;
            newDependency = nix;
          }
        ];
      }).overrideAttrs (_: {
        inherit (cached) meta version;
        disallowedReferences = [ cached prev.nix ];
      })
  ) { };
  nix-direnv = prev.nix-direnv.override { nix = prev.nixVersions.latest; };

  inherit (runtimeLibraries) watermark-pdf;
  split-pdf = prev.split-pdf.override { qpdf = runtimeLibraries.qpdf; };

  llmWithPlugins = prev.llmWithPlugins.override {
    extraLibs = builtins.attrValues llmRuntimeModules;
  };

  # The vanilla package (overlays/packages.nix), re-called with the
  # python set whose pymupdf rides the lite OCR chain above.
  remarks = prev.remarks.override {
    python3 = pythonForRemarks;
    python3Packages = pythonForRemarks.pkgs;
  };

  # pi-coding-agent's scripts are shebanged with the full nodejs join
  # (overlays/packages.nix builds it with the stable toolchain). The
  # residue hook re-points them at the runtime node, and drops npm and
  # corepack from the closure.
  # The install also keeps undeclared workspace packages and source maps.
  # Preserve runtime dependencies, TypeScript extension sources, and types.
  pi-coding-agent =
    let
      runtime = final.withoutNpmBuildResidue prev.pi-coding-agent;
    in
    prev.runCommand runtime.name
      {
        nativeBuildInputs = [ prev.nodejs-slim ];
        inherit (runtime) meta version;
        passthru = runtime.passthru or { };
      }
      ''
        cp -a ${runtime} $out
        chmod -R u+w $out
        node ${./prune-node-modules.js} $out/lib/node_modules/pi-monorepo --include-optional
        find $out -type f \( -name '*.js.map' -o -name '*.mjs.map' -o -name '*.cjs.map' -o -name '*.ts.map' -o -name '*.mts.map' \) -delete
        find $out -xtype l -delete
        find $out -type f -exec sed -i "s|${runtime}|$out|g" {} +
        ! grep -r ${runtime} $out
      '';

  # The pi wrapper (packages/pi/pi.nix), re-called with the runtime node
  # and the repacks: the runtime has `node`, which is all pnpm and pi run.
  pi = prev.pi.override {
    nodejs = final.nodejs-slim-runtime;
    pnpm = pnpmRuntime;
    inherit (final) pi-coding-agent playwright-lazy;
  };

  # Several of node's C dependencies have no dev output: headers, cmake
  # exports and build metadata ride in the runtime output (uvwasi's metadata
  # pins libuv's -dev headers). node links the libraries, never the
  # headers. Same name → same store path length, so the copies can
  # replace the originals byte-for-byte inside node's ELF below.
  withoutHeaders =
    pkg:
    prev.runCommand pkg.name { } ''
      cp -a ${pkg} $out
      chmod -R u+w $out
      rm -rf $out/include $out/lib/pkgconfig $out/lib/cmake
      rm -f $out/nix-support/propagated-build-inputs
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

  # NOTE: python3's runtime output carries ~68M of build-time material
  # (libpython.a + build config, IDLE, tests) shared by
  # modules/shared/environment.nix and the python package envs. A repack
  # works, but swapping it under the envs
  # needs nixpkgs' replaceDependency, whose import-from-derivation breaks
  # cross-platform eval (checking darwin outputs from linux); a partial
  # swap would duplicate the interpreter instead. Left whole on purpose.

  # OCR languages actually written here; the default tesseract wrapper
  # bundles ~120 of them — 1G of trained models. Re-wrapping is
  # data-only, nothing compiles.
  tesseract-lite = prev.tesseract.override {
    enableLanguages = [
      "eng"
      "ita"
      "spa"
    ];
  };

  # Build-hook flavor for packages we compile anyway (pi-coding-agent):
  # cached builds get the same scripts inside runCommand repacks instead.
  withoutNpmBuildResidue =
    drv:
    drv.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + npmResidueSweep;
      # postFixup, not postInstall: patchShebangs writes the node
      # references during fixup.
      postFixup = (old.postFixup or "") + nodeJoinRepoint;
    });

  # Repack of the cached build. dist/ is a self-contained webpack bundle —
  # typeshed and a vendored vscode-languageserver ride inside it — while
  # node_modules is 217M of pyright's monorepo tooling (@azure, prettier,
  # npm-check-updates) nothing loads; it also leaked npm-deps through
  # keytar's config.gypi and the node source through its depfiles. The
  # .maps only ever served the upstream debugger. The bin scripts are
  # text, so the full-nodejs shebang re-points at the runtime node
  # (attach + diagnostics verified by the variants check).
  basedpyright = prev.runCommand prev.basedpyright.name { inherit (prev.basedpyright) meta; } ''
    cp -a ${prev.basedpyright} $out
    chmod -R u+w $out
    rm -rf $out/lib/node_modules/pyright-root/node_modules
    rm -f $out/lib/node_modules/pyright-root/dist/*.map
    ${npmResidueSweep}
    ${nodeJoinRepoint}
    find $out -type f -exec sed -i "s|${prev.basedpyright}|$out|g" {} +
    # A leftover would silently keep the join or the npm FOD in the closure.
    ! grep -r ${prev.nodejs} $out
    ! grep -r ${prev.basedpyright.npmDeps} $out
  '';

  # The wrapper (overlays/packages.nix), re-called with a repack of the
  # cached build. katex's vendored python scripts otherwise pull an
  # interpreter into the closure; see npmResidueSweep.
  markdownlint-cli2 = prev.markdownlint-cli2.override (old: {
    markdownlint-cli2-unwrapped =
      let
        cached = old.markdownlint-cli2-unwrapped;
      in
      prev.runCommand cached.name { inherit (cached) meta; } ''
        cp -a ${cached} $out
        chmod -R u+w $out
        ${npmResidueSweep}
        ${nodeJoinRepoint}
        find $out -type f -exec sed -i "s|${cached}|$out|g" {} +
        ! grep -r ${prev.nodejs} $out
      '';
  });

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
    # A no-op swap (input drift after a bump) would silently keep node 22.
    grep -rq ${final.nodejs-slim-runtime} $out
    ! grep -rq ${prev.nodejs-slim_22} $out
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
        # A no-op swap would silently keep the npm/corepack join.
        grep -rq ${final.nodejs-slim-runtime} $out
        ! grep -rq ${prev.nodejs} $out
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
        # A no-op swap would silently keep the unstripped node.
        grep -rq ${final.nodejs-slim-runtime} $out
        ! grep -rq ${prev.nodejs-slim} $out
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
    prev.runCommand final.neovim-unwrapped.name
      {
        inherit (final.neovim-unwrapped) meta version;
        # nixCats builds the wrapper's lua env out of this passthru.
        passthru = {
          inherit (final.neovim-unwrapped) lua;
        };
      }
      ''
        cp -a ${final.neovim-unwrapped} $out
        chmod -R u+w $out
        rm -rf $out/share/locale $out/lib/nvim/parser
        # nvim embeds its own prefix (the default VIMRUNTIME); left alone
        # it chains the copy to the original and everything it references.
        find $out -type f -exec sed -i \
          -e "s|${final.neovim-unwrapped}|$out|g" \
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
    prev.runCommand "${final.neovim-unwrapped.name}-bare"
      {
        nativeBuildInputs = [ prev.makeWrapper ];
        inherit (final.neovim-unwrapped) meta;
      }
      ''
        install -Dm444 -t $out/rtp/parser ${final.neovim-unwrapped}/lib/nvim/parser/*.so
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
    prev.runCommand prev.marksman.name
      {
        nativeBuildInputs = [
          prev.removeReferencesTo
          final.patchelf
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
        # Leftovers would silently chain the copy back to the original
        # (and with it gettext and contrib's bash-interactive).
        ! grep -rq ${prev.gitMinimal} $out
        ! grep -rq ${prev.gettext} $out
      '';

  # Repack the cached rga wrappers without their bundled media converter.
  # FFmpeg can still be supplied on PATH for multimedia searches. Only
  # text wrappers carry these dependencies; leave the ELF binaries alone.
  ripgrep-all = prev.runCommand prev.ripgrep-all.name { inherit (prev.ripgrep-all) meta; } ''
    cp -a ${prev.ripgrep-all} $out
    chmod -R u+w $out
    grep -rlF ${prev.lib.getBin prev.ffmpeg} $out | while IFS= read -r f; do
      [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] && continue
      sed -i \
        -e "\|${prev.lib.getBin prev.ffmpeg}|d" \
        -e "s|${prev.ripgrep-all}|$out|g" "$f"
    done
  '';

  # Linux MCP runs headless, so ship the cached Chromium headless shell.
  # Use the MCP source and core driver so builds do not fetch the full browser farm.
  playwright-lazy =
    let
      source = prev.lib.findFirst (input: toString input == toString prev.path)
        (throw "No locked nixpkgs input matches the browser package set")
        [ self.inputs.nixpkgs self.inputs.nixpkgs-unstable self.inputs.nixpkgs-darwin ];
      pin = {
        type = "github";
        owner = "NixOS";
        repo = "nixpkgs";
        inherit (source) rev narHash;
      };
      cachedSource = builtins.unsafeDiscardStringContext (builtins.baseNameOf source.outPath);
      browserPkgs = import source { system = prev.stdenv.hostPlatform.system; };
      browser = import ./playwright-browser.nix {
        pkgs = browserPkgs;
        runtimeLibraries = import ./runtime-libraries.nix { pkgs = browserPkgs; };
      };
      browserExpression = prev.writeText "playwright-browser.nix" ''
        let
          # The source path is a hint. Do not retain it in the runtime closure.
          cached = builtins.storeDir + "/${builtins.substring 0 16 cachedSource}"
            + "${builtins.substring 16 256 cachedSource}";
          source = if builtins.pathExists cached then cached
            else builtins.fetchTree (builtins.fromJSON ${builtins.toJSON (builtins.toJSON pin)});
          pkgs = import source {
            system = ${builtins.toJSON prev.stdenv.hostPlatform.system};
          };
          runtimeLibraries = import ${./runtime-libraries.nix} { inherit pkgs; };
        in import ${./playwright-browser.nix} { inherit pkgs runtimeLibraries; }
      '';
      browserLauncher = prev.callPackage ./playwright-lazy.nix {
        inherit browserExpression;
        nix = prev.nixVersions.latest;
      };
      browserConfig = prev.writeText "playwright-lazy.json" (builtins.toJSON {
        browser.launchOptions.timeout = 600000;
      });
      playwright-core = prev.runCommand prev.playwright-driver.name { } ''
        cp -a ${prev.playwright-driver} "$out"
        chmod -R u+w "$out"
        find "$out" -name '*.d.ts' -delete
        rm -rf "$out/lib/vite"
        ${nodeJoinRepoint}
        ! grep -r ${prev.nodejs} "$out"
      '';
    in
    prev.runCommand "playwright-lazy-${prev.playwright-mcp.version}"
      {
        nativeBuildInputs = [ prev.makeWrapper ];
        meta = prev.playwright-mcp.meta // {
          mainProgram = "playwright-lazy";
          description = "Playwright MCP with Chromium installed on first use";
        };
        passthru = { inherit browser browserExpression browserLauncher; };
      }
      ''
        pkg="$out/lib/node_modules/playwright-mcp-internal"
        mkdir -p "$pkg/node_modules" "$out/bin"
        cp ${prev.playwright-mcp.src}/packages/playwright-mcp/{cli.js,index.js,package.json} "$pkg/"
        cp ${prev.playwright-mcp.src}/LICENSE "$pkg/"
        ln -s ${playwright-core} "$pkg/node_modules/playwright-core"
        makeWrapper ${final.nodejs-slim-runtime}/bin/node "$out/bin/playwright-lazy" \
          --add-flags "$pkg/cli.js --config ${browserConfig}" \
          --set-default PLAYWRIGHT_MCP_EXECUTABLE_PATH ${browserLauncher}/bin/playwright-browser \
          --set-default PLAYWRIGHT_MCP_BROWSER chromium
        ln -s ${browserLauncher}/bin/playwright-browser-prefetch "$out/bin/playwright-browser-prefetch"
      '';

  # Repack of the cached build. nixpkgs ships codex unstripped: of the
  # 373M main binary, ~72M is .symtab/.strtab only a debugger reads.
  # strip is data-only — the .dep-v0 section stays so cargo-auditable
  # tooling can still read the dependency record. Linux-only: GNU strip
  # cannot edit Mach-O, and on darwin it would invalidate the signature.
  codex =
    let
      cached = prev.codex;
      hasVoice = builtins.elem "codex-voice-host" (cached.cargoBuildFlags or [ ]);
      replacements = prev.lib.optionals hasVoice runtimeLibraries.codexVoice;
      # Header paths only identify references to erase; realizing their
      # outputs would needlessly build the compiler/libc development files.
      buildOnlyReferences = map (p: builtins.unsafeDiscardStringContext (toString p)) [
        prev.stdenv.cc.cc
        prev.stdenv.cc.libc.dev
      ];
    in
    prev.runCommand cached.name
      {
        nativeBuildInputs = [
          prev.binutils
          prev.removeReferencesTo
        ];
        inherit (cached) meta version;
        passthru = (cached.passthru or { }) // {
          tests =
            (cached.tests or { })
            // prev.lib.optionalAttrs hasVoice {
              voice-runtime = cached.tests.voice-runtime.override {
                codex = final.codex // {
                  inherit (cached) buildCommit;
                };
              };
              app-server-daemon = cached.tests.app-server-daemon.override { codex = final.codex; };
            };
        };
        disallowedReferences = [
          cached
        ]
        ++ map (r: r.oldDependency) replacements
        ++ prev.lib.optionals hasVoice buildOnlyReferences;
      }
      ''
        cp -a ${cached} $out
        chmod -R u+w $out
        find $out -type f -executable -exec strip --keep-section=.dep-v0 {} +
        # bin/codex is a binary wrapper pinning the original's prefix and
        # PATH; same names → equal lengths, safe inside the ELF.
        find $out -type f -exec sed -i "s|${cached}|$out|g" {} +
        ${prev.lib.concatMapStringsSep "\n" (r: ''
          find $out -type f -exec sed -i "s|${r.oldDependency}|${r.newDependency}|g" {} +
          find $out -type l -lname '${r.oldDependency}/*' -print0 | while IFS= read -r -d ''' link; do
            target=$(readlink "$link")
            ln -sfn "${r.newDependency}/''${target#${r.oldDependency}/}" "$link"
          done
        '') replacements}
        ${prev.lib.optionalString hasVoice ''
          # bindgen embeds compiler/header locations in the voice helper's
          # diagnostics. They are build metadata, not runtime dependencies.
          find $out -type f -exec remove-references-to \
            ${prev.lib.concatMapStringsSep " " (p: "-t ${p}") buildOnlyReferences} {} +
        ''}
        # A leftover would silently chain the copy to the original; a
        # no-op strip would silently keep the symbol tables. The layout
        # shifts across versions (0.133 ships one binary, 0.144 three),
        # so sweep every ELF rather than naming one.
        ! grep -r ${cached} $out
        find $out -type f -executable | while IFS= read -r f; do
          [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] || continue
          if readelf -SW "$f" | grep -qe '\.symtab'; then
            echo "unstripped: $f"; exit 1
          fi
        done
      '';
  };
in

# The repacks buy closure size on the Linux hosts and cost correctness on
# darwin, where rewriting a store path inside a Mach-O invalidates the ad-hoc
# code signature the kernel then refuses to run (`Killed: 9`, no load error).
# Hand back the stock packages there, keeping the runtime names the rest of the
# repo consumes so nothing has to know which platform it is on.
if prev.stdenv.hostPlatform.isLinux then
  slimmed
else
  builtins.intersectAttrs slimmed prev
  // {
    # The MCP wrapper changes scripts and keeps the signed browser intact.
    inherit (slimmed) playwright-lazy;
    withoutHeaders = pkg: pkg;
    withoutNpmBuildResidue = pkg: pkg;
    gitMinimal-runtime = prev.gitMinimal;
    tesseract-lite = prev.tesseract;
    neovim-bare = prev.neovim;
    neovim-unwrapped-runtime = final.neovim-unwrapped;
    nodejs-slim-runtime = prev.nodejs-slim;
    tree-sitter-runtime = prev.tree-sitter;
  }
