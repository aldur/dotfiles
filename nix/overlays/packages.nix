final: prev: {
  tiktoken = (prev.callPackage ../packages/tiktoken/tiktoken.nix { });
  llmcat = (prev.callPackage ../packages/llmcat/llmcat.nix { });
  llm-mlx = (prev.callPackage ../packages/llm-mlx/default.nix { });
  nomicfoundation-solidity-language-server = (prev.callPackage
    ../packages/nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
    { });
  gpg-encrypt = (prev.callPackage ../packages/gpg-encrypt/gpg-encrypt.nix { });
}
