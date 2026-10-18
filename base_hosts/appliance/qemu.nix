{ inputs, lib, ... }:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./guest.nix
  ];
  # The development guest's flake-copy helper needs Home Manager.
  disabledModules = [ "${inputs.self}/modules/current_system_flake.nix" ];

  virtualisation = {
    graphics = true;
    qemu.guestAgent.enable = false;
    writableStore = lib.mkForce false;
    fileSystems = {
      "/" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=755" "nosuid" "nodev" "size=1G" ];
      };
      "/state" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        neededForBoot = true;
        options = [ "nosuid" "nodev" ];
      };
      # Keep shutdown ordering when systemd removes the mountinfo dependencies.
      "/nix/.ro-store".options = [ "x-systemd.before=umount.target" ];
    };
  };
  hardware.graphics.enable = true;
  services.getty.autologinUser = lib.mkForce null;
}
