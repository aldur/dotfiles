# Full-system image for `container machine`.
#
# Unlike the lightweight `apple-container.nix` (one process under `container
# run`), a *container machine* runs the image's own init: Apple execs
# `/sbin/init`, which here is the NixOS stage-2 init — it performs activation
# and then hands off to systemd as PID 1. So this behaves like a small,
# persistent Linux box you log into (`container machine run`), with real service
# management, a nix-daemon, journald, etc. — closer to the `crostini`/`qemu`
# hosts than to a container.
#
# Everything but the boot model is shared with the lightweight image via
# `common.nix`; there is no hand-rolled activation entrypoint here because
# systemd does it all properly.
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

  networking.hostName = "apple-machine";

  system.build.containerImage = mkOciArchive {
    name = "aldur-nixos-machine";
    layered = pkgs.dockerTools.buildLayeredImage {
      name = "aldur-nixos-machine";
      tag = "latest";

      includeNixDB = true;

      # `container machine` execs `/sbin/init`. Point it at the NixOS stage-2
      # init (the same one nixos-containers/LXC boot through), which runs
      # activation and then systemd. /tmp must be world-writable+sticky.
      extraCommands = ''
        mkdir -p sbin proc sys dev etc run tmp var
        ln -sfn ${toplevel}/init sbin/init
        chmod 1777 tmp
      '';

      # Also reference the init as the OCI Cmd: it pulls the toplevel closure
      # into the image (so /sbin/init resolves) and serves as a fallback for
      # runtimes that honour the OCI entrypoint rather than execing /sbin/init.
      config.Cmd = [ "${toplevel}/init" ];
    };
  };
}
