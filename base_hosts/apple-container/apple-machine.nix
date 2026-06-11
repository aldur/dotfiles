{
  config,
  pkgs,
  lib,
  mkOciArchive,
  ...
}:
let
  toplevel = config.system.build.toplevel;
in
{
  imports = [ ./common.nix ];

  networking.hostName = "nixos-apple-vm";

  # Apple's `container machine` bootstrap (`configureDns`/`configureHosts`,
  # before the guest boots) writes /etc/resolv.conf and /etc/hosts into the
  # image's rootfs. vminitd already assigns the IP/route, so the guest must not
  # run its own DHCP, and must not let resolvconf replace /etc/resolv.conf with
  # a (dangling) symlink afterwards — both would fight Apple's DNS setup.
  networking.useDHCP = false;
  networking.resolvconf.enable = lib.mkForce false;

  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos-machine";
    stream = pkgs.dockerTools.streamLayeredImage {
      name = "aldur-nixos-machine";
      tag = "latest";

      includeNixDB = true;

      # /sbin/init -> the NixOS stage-2 init. Also ship real (placeholder)
      # /etc/resolv.conf and /etc/hosts so /etc is a guaranteed-present writable
      # directory (empty dirs can be dropped in layer/OCI conversion) that
      # Apple's bootstrap can write into.
      extraCommands = ''
        mkdir -p sbin proc sys dev etc run tmp var
        ln -sfn ${toplevel}/init sbin/init
        : > etc/resolv.conf
        printf '127.0.0.1 localhost\n' > etc/hosts
        chmod 1777 tmp
      '';

      config.Cmd = [ "${toplevel}/init" ];
    };
  };
}
