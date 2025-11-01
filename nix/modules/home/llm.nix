{ pkgs, config, lib, ... }:
let cfg = config.programs.llm;
in {

  options.programs.llm = { enable = lib.mkEnableOption "simonw's LLM"; };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs;
      [
        (python312.withPackages (ps:
          [ ps.llm ps.llm-ollama ps.llm-gguf llm-mlx ]
          ++ lib.optional (stdenv.isDarwin) llm-mlx))
      ];
  };
}
