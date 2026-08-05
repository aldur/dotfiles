{ self }:
final: prev: {
  nomicfoundation-solidity-language-server =
    prev.callPackage
      ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { };

  solidity-docset = prev.callPackage ../packages/solidity-docset { };

  gpg-encrypt = prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { };
  totp-cli = final.callPackage ../packages/totp-cli-ephemeral { inherit (prev) totp-cli; };

  # Headless: they only shell out to `gs`, and the default ghostscript build
  # carries X11 and gtk (~95M) for a window no wrapper ever opens.
  shrink-pdf = prev.callPackage ../packages/shrink-pdf { ghostscript = prev.ghostscript_headless; };
  flatten-pdf = prev.callPackage ../packages/flatten-pdf { ghostscript = prev.ghostscript_headless; };
  watermark-pdf = prev.callPackage ../packages/watermark-pdf { };
  split-pdf = prev.callPackage ../packages/split-pdf { };
  totp-qr-decode = prev.callPackage ../packages/totp-qr-decode { };
  flake-lock-cooldown = prev.callPackage ../packages/flake-lock-cooldown { };
  neovim-nightly = prev.callPackage ../packages/neovim-nightly { };

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
    });

  basedpyright = final.withoutNpmBuildResidue prev.basedpyright; # Leaks npm-deps through keytar's config.gypi.
  aldurs-dotfiles-version = prev.callPackage ../packages/aldurs-dotfiles-version { inherit self; };
  faraday = prev.callPackage ../packages/faraday { };
  fps = prev.callPackage ../packages/fps { };
  lstrip = prev.callPackage ../packages/lstrip { };
  claude-log = prev.callPackage ../packages/claude-log { };
  claude-skills = prev.callPackage ../packages/claude-skills { };
  telegram = prev.callPackage ../packages/telegram { };
  remarks = prev.callPackage ../packages/remarks { };
  tmux-palette = prev.callPackage ../packages/tmux-palette { };
  tcopy = prev.callPackage ../packages/tcopy { };
  lazyvim-popup = prev.callPackage ../packages/lazyvim-popup { };
  taskmd = prev.callPackage ../packages/taskmd { };

  tiktoken = prev.callPackage ../packages/tiktoken/tiktoken.nix { };
  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };

  # pi releases often; stable nixpkgs lags too far behind, so follow
  # unstable by default. `legacyPackages` (rather than a fresh `import`)
  # reuses the flake's memoized, un-overlaid package set.
  pi-coding-agent =
    self.inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.pi-coding-agent;

  piPlugins = {
    pi-llama = prev.callPackage ../packages/pi/plugins/pi-llama.nix { };
  };
  pi = prev.callPackage ../packages/pi/pi.nix {
    plugins = final.piPlugins;
    # pi-coding-agent (above) comes from unstable; hand the wrapper the same
    # channel's node and pnpm so the closure carries one copy, not twins.
    inherit (self.inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system})
      nodejs
      pnpm
      ;
  };

  # Rust port of pi, wrapped with the same affordances (plugin bundling, no
  # phone-home); the binary is `pi-rust` so both can sit on PATH. No plugins:
  # pi-llama's job is done by the built-in `llamacpp` provider.
  pi-agent-rust = prev.callPackage ../packages/pi-rust/pi-agent-rust.nix { };
  pi-rust = prev.callPackage ../packages/pi-rust/pi-rust.nix { };

  llm-mlx = prev.callPackage ../packages/llm-mlx { };
  llmWithPlugins = prev.python3.withPackages (
    ps:
    [
      ps.llm
      ps.llm-ollama
      ps.llm-gguf
      ps.llm-openrouter
      ps.llm-docs
      ps.llm-llama-server
    ]
    ++ prev.lib.optional (prev.stdenv.isDarwin && prev.stdenv.isAarch64) final.llm-mlx
  );

  markdownlint-cli2 = final.callPackage ../packages/markdownlint-cli2 {
    # katex's vendored python scripts otherwise pull an interpreter into
    # the closure; see withoutNpmBuildResidue.
    markdownlint-cli2-unwrapped = final.withoutNpmBuildResidue prev.markdownlint-cli2;
  };

  uvc-util = prev.callPackage ../packages/uvc-util { };
  c920-defaults = final.callPackage ../packages/c920-defaults { };
}
