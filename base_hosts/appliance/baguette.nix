{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nixos-crostini.nixosModules.baguette
    ./guest.nix
  ];
  hardening.foreignKernel = true;
  users.users.${config.mainUser}.crostini.enable = true;
  baguette = {
    ephemeralRoot = {
      enable = true;
      tmpfsSize = "1G";
      mountOptions = [ "nosuid" "nodev" ];
    };
    portListener.enable = false;
    notifications.enable = false;
  };
  crostini.extraTools.enable = false;
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
