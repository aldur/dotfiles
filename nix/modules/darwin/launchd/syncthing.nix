{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  name = "syncthing";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "Syncthing";
  };

  config = mkIf cfg.enable {
    launchd = {
      user = {
        agents = {
          syncthing = {
            command = "${pkgs.lib.getExe pkgs.syncthing} --no-browser --no-restart";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
            };
          };

        };
      };
    };
  };
}
