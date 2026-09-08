{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.programs = {
    llm.enable = lib.mkEnableOption "the datasette llm CLI with its plugins";
    llama-cpp.enable = lib.mkEnableOption "the llama.cpp server and tools";
    pi.enable = lib.mkEnableOption "the pi coding agent with its plugins";
  };

  config.home.packages =
    lib.optionals config.programs.llm.enable [ pkgs.llmWithPlugins ]
    ++ lib.optionals config.programs.llama-cpp.enable [ pkgs.llama-cpp ]
    ++ lib.optionals config.programs.pi.enable [ pkgs.pi ];
}
