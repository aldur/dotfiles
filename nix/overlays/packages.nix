final: prev: {
  nomicfoundation-solidity-language-server =
    prev.callPackage
      ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { };

  gpg-encrypt = prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { };
  totp-cli = final.callPackage ../packages/totp-cli-ephemeral/default.nix {
    inherit (prev) totp-cli symlinkJoin makeWrapper;
  };

  tiktoken = prev.callPackage ../packages/tiktoken/tiktoken.nix { };
  llmcat = prev.callPackage ../packages/llmcat/llmcat.nix { };
  llm-mlx = prev.callPackage ../packages/llm-mlx/default.nix { };
  mlx = prev.callPackage ../packages/mlx { };
  llmWithPlugins = prev.python3.withPackages (
    ps:
    [
      ps.llm
      ps.llm-ollama
      ps.llm-gguf
    ]
    ++ prev.lib.optional prev.stdenv.isDarwin final.llm-mlx
  );
}
