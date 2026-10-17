{
  config,
  lib,
  pkgs,
  ...
}:
let
  image = import ../../../utils/qemu-store-image.nix {
    inherit pkgs;
    inherit (config.system.build) toplevel;
    regInfo = pkgs.closureInfo { rootPaths = config.virtualisation.additionalPaths; };
    compress = true;
    compressor = "lz4";
  };
in
{
  # Disable the unused store image that the upstream launcher creates at boot.
  virtualisation.useNixStoreImage = lib.mkForce false;
  virtualisation.mountHostNixStore = false;
  virtualisation.fileSystems = {
    "/nix/.ro-store" = {
      device = "/dev/disk/by-label/nix-store";
      fsType = "erofs";
      neededForBoot = true;
      options = [ "ro" ];
    };
    "/nix/store" = {
      overlay = {
        lowerdir = [ "/nix/.ro-store" ];
        upperdir = "/nix/.rw-store/upper";
        workdir = "/nix/.rw-store/work";
      };
    };
  };
  virtualisation.qemu.drives = lib.mkForce [
    {
      name = "root";
      file = ''"$NIX_DISK_IMAGE"'';
      driveExtraOpts = {
        cache = "writeback";
        werror = "report";
      };
      deviceExtraOpts = {
        bootindex = "1";
        serial = "root";
      };
    }
    {
      name = "nix-store";
      file = "${image}/store.img";
      driveExtraOpts = {
        format = "raw";
        readonly = "on";
      };
      deviceExtraOpts.bootindex = "2";
    }
  ];
}
