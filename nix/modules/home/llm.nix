{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.llm;
in
{

  options.programs.llm = {
    enable = lib.mkEnableOption "LLMs tools and friends";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      llmWithPlugins
      llama-cpp
    ];
  };
}
