final: prev: {
  tiktoken = (prev.callPackage ../packages/tiktoken/tiktoken.nix { });
  llmcat = (prev.callPackage ../packages/llmcat/llmcat.nix { });
  llm-mlx = (prev.callPackage ../packages/llm-mlx/default.nix { });
  dashp = (prev.callPackage ../packages/dashp/dashp.nix { });
}
