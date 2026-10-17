{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.self.nixosModules.baguette-guest
    ./guest.nix
  ];
  hardening.foreignKernel = true;
  baguette.ephemeralRoot = {
    enable = true;
    tmpfsSize = "1G";
  };
  # systemd-remount-fs applies these to the overlay declared by nixos-crostini.
  fileSystems."/".options = [ "nosuid" "nodev" ];
  systemd.services.cros-port-listener.enable = false;
  systemd.user.services.cros-notificationd.enable = false;
  hardware.graphics.enable = false;
  virtualisation = {
    buildMemorySize = 4096;
    # ChromeOS expands this filesystem to the requested VM size.
    # Set virtualisation.diskImageSize = lib.mkForce 8192; to use an 8 GiB seed image.
    diskImageSize = 4096;
  };
  system.build.btrfsImageCompressed = lib.mkForce (
    pkgs.runCommand "nixos-baguette-btrfs-compressed" { nativeBuildInputs = [ pkgs.zstd ]; } ''
      mkdir -p $out
      zstd -19 -T4 ${config.system.build.btrfsImage}/baguette_rootfs.img \
        -o $out/baguette_rootfs.img.zst
    ''
  );
}
