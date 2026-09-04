{ self }:
final: prev:
let
  # `legacyPackages` reuses the flake's memoized, un-overlaid package set.
  unstable = self.inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system};
in
{
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
  update-pins = prev.callPackage ../packages/update-pins { };
  neovim-nightly = prev.callPackage ../packages/neovim-nightly { };

  aldurs-dotfiles-version = prev.callPackage ../packages/aldurs-dotfiles-version { inherit self; };
  faraday = prev.callPackage ../packages/faraday { };
  fps = prev.callPackage ../packages/fps { };
  lstrip = prev.callPackage ../packages/lstrip { };
  trim = prev.callPackage ../packages/trim { };
  claude-skills = prev.callPackage ../packages/claude-skills { };
  telegram = prev.callPackage ../packages/telegram { };
  remarks = prev.callPackage ../packages/remarks { };
  tmux-palette = prev.callPackage ../packages/tmux-palette { };
  tcopy = prev.callPackage ../packages/tcopy { };
  lazyvim-popup = prev.callPackage ../packages/lazyvim-popup { };
  taskmd = prev.callPackage ../packages/taskmd { };
  taskmd-ui = final.callPackage ../packages/taskmd-ui { };

  tiktoken = prev.callPackage ../packages/tiktoken/tiktoken.nix { };
  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };

  # pi releases often; stable nixpkgs lags too far behind, so follow
  # unstable by default. Build it with the stable Node toolchain: slim.nix
  # re-points the stable node paths at the one runtime node of this repo,
  # and an unstable node would stay behind as a twin. Both channels ship
  # Node 24, which strips TS types by default.
  pi-coding-agent = unstable.pi-coding-agent.override { inherit (prev) buildNpmPackage; };

  piPlugins = {
    pi-llama = prev.callPackage ../packages/pi/plugins/pi-llama.nix { };
    # final.callPackage: the build-time check must see the same
    # pi-coding-agent (above) that the wrapper runs.
    pi-no-docs = final.callPackage ../packages/pi/plugins/pi-no-docs { };
    pi-statusline = prev.callPackage ../packages/pi/plugins/pi-statusline { };
    pi-system-prompt = prev.callPackage ../packages/pi/plugins/pi-system-prompt { };
  };
  pi = prev.callPackage ../packages/pi/pi.nix { plugins = final.piPlugins; };

  # Rust port of pi, wrapped with the same affordances (plugin bundling, no
  # phone-home); the binary is `pi-rust` so both can sit on PATH. No plugins:
  # pi-llama's job is done by the built-in `llamacpp` provider.
  pi-rust = unstable.callPackage ../packages/pi-rust/pi-rust.nix { };

  llama-wiretap = final.callPackage ../packages/llama-wiretap {
    nodejs-slim = final.nodejs-slim-runtime;
  };

  agent-log = final.callPackage ../packages/agent-log { };

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
    ++ prev.lib.optional (
      prev.stdenv.hostPlatform.isDarwin && prev.stdenv.hostPlatform.isAarch64
    ) final.llm-mlx
  );

  markdownlint-cli2 = final.callPackage ../packages/markdownlint-cli2 {
    # katex's vendored python scripts otherwise pull an interpreter into
    # the closure; see withoutNpmBuildResidue.
    markdownlint-cli2-unwrapped = final.withoutNpmBuildResidue prev.markdownlint-cli2;
  };

  uvc-util = prev.callPackage ../packages/uvc-util { };
  c920-defaults = final.callPackage ../packages/c920-defaults { };
}
