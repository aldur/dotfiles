final: prev: {
  nomicfoundation-solidity-language-server =
    prev.callPackage
      ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { };

  solidity-docset = prev.callPackage ../packages/solidity-docset { };

  gpg-encrypt = prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { };
  totp-cli = final.callPackage ../packages/totp-cli-ephemeral { inherit (prev) totp-cli; };

  shrink-pdf = prev.callPackage ../packages/shrink-pdf { };
  flatten-pdf = prev.callPackage ../packages/flatten-pdf { };
  watermark-pdf = prev.callPackage ../packages/watermark-pdf { };
  split-pdf = prev.callPackage ../packages/split-pdf { };
  totp-qr-decode = prev.callPackage ../packages/totp-qr-decode { };
  flake-lock-cooldown = prev.callPackage ../packages/flake-lock-cooldown { };
  faraday = prev.callPackage ../packages/faraday { };
  fps = prev.callPackage ../packages/fps { };
  lstrip = prev.callPackage ../packages/lstrip { };
  claude-log = prev.callPackage ../packages/claude-log { };
  telegram = prev.callPackage ../packages/telegram { };
  remarks = prev.callPackage ../packages/remarks { };
  tmux-palette = prev.callPackage ../packages/tmux-palette { };
  lazyvim-popup = prev.callPackage ../packages/lazyvim-popup { };

  tiktoken = prev.callPackage ../packages/tiktoken/tiktoken.nix { };
  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };

  llmWithPlugins = prev.python3.withPackages (
    ps:
    [
      ps.llm
      ps.llm-ollama
      ps.llm-gguf
      ps.llm-openrouter
      ps.llm-docs
    ]
    ++ prev.lib.optional (prev.stdenv.isDarwin && prev.stdenv.isAarch64) (
      prev.callPackage ../packages/llm-mlx { }
    )
  );

  markdownlint-cli2 = final.callPackage ../packages/markdownlint-cli2 {
    markdownlint-cli2-unwrapped = prev.markdownlint-cli2;
  };

  uvc-util = prev.callPackage ../packages/uvc-util { };
  c920-defaults = final.callPackage ../packages/c920-defaults { };
}
