{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.programs.llm.enable = lib.mkEnableOption "the datasette llm CLI with its plugins";

  config.home.packages = lib.optionals config.programs.llm.enable [ pkgs.llmWithPlugins ];
}
