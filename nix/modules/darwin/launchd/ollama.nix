{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  name = "ollama";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "Ollama server";
  };

  config = mkIf cfg.enable {
    launchd = {
      user = {
        agents = {

          ollama = {
            command = "${pkgs.lib.getExe pkgs.ollama} serve";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
            };
            environment = {
              OLLAMA_FLASH_ATTENTION = "1";
              OLLAMA_KV_CACHE_TYPE = "q8_0";
            };
          };
        };
      };
    };
  };
}
