# Replaces the Debian guest of the Android Terminal app. The guest
# interface comes from the AOSP Debian image (build/debian in
# platform/packages/modules/Virtualization): the app boots its own kernel
# with root=/dev/vda1, attaches cidata.iso as /dev/vdb, shares Android
# storage as the virtiofs tag `android`, and opens ttyd on vsock port 7681.
{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  systemConfig = config.system.build.toplevel;

  # The kernel starts /sbin/init. Stage 1 of NixOS makes the /dev/fd links
  # that stage 2 needs, and this guest has no stage 1.
  installInit = pkgs.writeShellApplication {
    name = "install-sbin-init";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mkdir -p /sbin
      cat > /sbin/init.tmp <<EOF
      #!${pkgs.runtimeShell}
      ${pkgs.coreutils}/bin/ln -sfn /proc/self/fd /dev/fd
      ${pkgs.coreutils}/bin/ln -sfn /proc/self/fd/0 /dev/stdin
      ${pkgs.coreutils}/bin/ln -sfn /proc/self/fd/1 /dev/stdout
      ${pkgs.coreutils}/bin/ln -sfn /proc/self/fd/2 /dev/stderr
      exec $1/init
      EOF
      chmod 755 /sbin/init.tmp
      mv /sbin/init.tmp /sbin/init
    '';
  };

  # install.sh makes this the init of the Debian guest. On the next boot,
  # the kernel starts it as PID 1. It moves the Debian files to /old-root,
  # as NIXOS_LUSTRATE does in stage 1, and starts stage 2.
  lustrateInit = pkgs.writeShellApplication {
    name = "nixos-lustrate-init";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    # The kernel starts init without PATH.
    inheritPath = false;
    text = ''
      shopt -s nullglob dotglob

      # The kernel mounts the root read-only and mounts only devtmpfs. The
      # fstab of Debian names the root by PARTUUID, and no udev links exist.
      # Do not mount /proc: stage 2 mounts the special file systems only if
      # /proc is empty.
      mount -n --options-source=disable -o remount,rw none /

      echo "Moving the Debian root to /old-root"
      mkdir -p /old-root.tmp
      for d in /*; do
        case "$d" in
        # /dev is a mount point. Stage 2 mounts on the others.
        /nix | /nix-path-registration | /dev | /proc | /sys | /run | /lost+found | /old-root.tmp) continue ;;
        esac
        mv "$d" /old-root.tmp/
      done
      mv /old-root.tmp /old-root

      mkdir /etc
      touch /etc/NIXOS
      ${lib.getExe installInit} ${systemConfig}
      sync

      exec /sbin/init
    '';
  };
  ttydSocket = "/run/ttyd/ttyd.sock";

  upgrade = pkgs.writeArgcApplication {
    name = "avf-upgrade";
    file = ./upgrade.sh;
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.unzip
      pkgs.util-linux
      config.nix.package
      config.system.build.nixos-rebuild
    ];
  };

in
{
  imports = [
    ./agent.nix
    ./terminal-display.nix
  ];

  hardening.foreignKernel = true;

  boot = {
    # The app supplies the kernel. Its initramfs has no /init, so the
    # kernel mounts the root and starts /sbin/init (stage 2).
    kernel.enable = false;
    kexec.enable = false;
    initrd.enable = false;
    kernelModules = lib.mkForce [ ];
    loader.grub.enable = false;
    loader.external = {
      enable = true;
      installHook = lib.getExe installInit;
    };
  };

  # From the LXC container module of nixpkgs. The app closes when ttyd is
  # not ready 30 s after the start, so this does not block sysinit.target.
  systemd.services.register-nix-paths = {
    description = "Register the paths of the tarball in the Nix database";
    unitConfig.ConditionPathExists = "/nix-path-registration";
    wantedBy = [ "multi-user.target" ];
    # Not before nix-daemon.socket: basic.target comes after sockets.target.
    before = [ "nix-daemon.service" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration
      rm /nix-path-registration
      ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
    '';
  };

  environment.systemPackages = [ upgrade ];

  # The kernel has no modules for the guest.
  system.activationScripts.modprobe = lib.mkForce "";
  system.activationScripts.rmmodBlacklisted = lib.mkForce "";

  fileSystems = {
    "/" = {
      device = "/dev/vda1";
      fsType = "ext4";
      options = [ "discard" ];
      # The app makes root_part larger when the user resizes the disk.
      autoResize = true;
    };
    "/mnt/shared" = {
      device = "android";
      fsType = "virtiofs";
      options = [
        "nofail"
        "x-systemd.automount"
      ];
    };
  };

  networking = {
    # The kernel has no nftables limit and log expressions (CONFIG_NFT_LIMIT,
    # CONFIG_NFT_LOG). It has the x_tables matches and targets.
    firewall.package = pkgs.iptables-legacy;
    useNetworkd = true;
    # As in the cloud-init network-config of the Debian guest.
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };
  systemd.network.networks."40-terminal" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "yes";
    dhcpV4Config.UseDNS = false;
    dhcpV6Config.UseDNS = false;
  };

  services.ttyd = {
    enable = true;
    socket = ttydSocket;
    writeable = true;
    entrypoint = [
      "${pkgs.shadow}/bin/login"
      "-f"
      config.mainUser
    ];
    clientOptions.disableLeaveAlert = "true";
  };
  systemd.services.ttyd.serviceConfig = {
    RuntimeDirectory = "ttyd";
    Restart = "always";
    RestartSec = 3;
  };

  # The bridge of the app tries again when the guest refuses the vsock
  # connection. When socat accepts and closes it, the WebView gets an error.
  # As in the Debian guest, listen only when ttyd is ready.
  systemd.paths.ttyd-vsock-bridge = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExists = ttydSocket;
  };
  systemd.services.ttyd-vsock-bridge = {
    description = "Bridge from vsock port 7681 to ttyd";
    requires = [ "ttyd.service" ];
    after = [ "ttyd.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.socat} VSOCK-LISTEN:7681,fork,reuseaddr UNIX-CONNECT:${ttydSocket}";
      Restart = "always";
      RestartSec = 3;
      # socat exits with 143 on SIGTERM.
      SuccessExitStatus = 143;
    };
  };

  # As in the Debian guest.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  system.build.avfImage = pkgs.callPackage "${toString modulesPath}/../lib/make-system-tarball.nix" {
    fileName = "nixos-terminal";
    contents = [ ];
    storeContents = [
      {
        object = lib.getExe lustrateInit;
        symlink = "/nixos-lustrate-init";
      }
      {
        object = systemConfig;
        symlink = "/nixos-system";
      }
    ];
    compressCommand = "pigz -9";
    compressionExtension = ".gz";
    extraInputs = [ pkgs.pigz ];
  };
}
