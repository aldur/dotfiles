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
    enable = lib.mkEnableOption "simonw's LLM";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.llmWithPlugins ];
  };
}
