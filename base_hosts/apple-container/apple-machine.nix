{
  config,
  pkgs,
  mkOciArchive,
  ...
}:
let
  toplevel = config.system.build.toplevel;
in
{
  imports = [ ./common.nix ];

  networking.hostName = "nixos-apple-vm";

  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos-machine";
    stream = pkgs.dockerTools.streamLayeredImage {
      name = "aldur-nixos-machine";
      tag = "latest";

      includeNixDB = true;

      extraCommands = ''
        mkdir -p sbin proc sys dev etc run tmp var
        ln -sfn ${toplevel}/init sbin/init
        chmod 1777 tmp
      '';

      config.Cmd = [ "${toplevel}/init" ];
    };
  };
}
