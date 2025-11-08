final: prev: {
  nomicfoundation-solidity-language-server =
    prev.callPackage
      ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { };

  gpg-encrypt = prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { };
  totp-cli = final.callPackage ../packages/totp-cli-ephemeral { inherit (prev) totp-cli; };

  shrinkpdf = prev.callPackage ../packages/shrinkpdf/shrinkpdf.nix { };
  tiktoken = prev.callPackage ../packages/tiktoken/tiktoken.nix { };
  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };

  llmWithPlugins = prev.python3.withPackages (
    ps:
    [
      ps.llm
      ps.llm-ollama
      ps.llm-gguf
    ]
    ++ prev.lib.optional (prev.stdenv.isDarwin && prev.stdenv.isAarch64) (
      prev.callPackage ../packages/llm-mlx { }
    )
  );

  markdownlint-cli2 = final.callPackage ../packages/markdownlint-cli2 {
    markdownlint-cli2-unwrapped = prev.markdownlint-cli2;
  };
}
