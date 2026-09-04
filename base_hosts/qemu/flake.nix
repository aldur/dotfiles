{
  description = "A QEMU NixOS guest from aldur's dotfiles.";

  inputs = {
    aldur-dotfiles = {
      # url = "git+file://../../..";
      url = "github:aldur/dotfiles";
    };
  };
  outputs =
    { aldur-dotfiles, ... }@inputs:
    aldur-dotfiles.lib.mkQemuGuest {
      inherit inputs;
      name = "vm-nogui";
      hostName = "qemu-nixos";
      qemuModule = ./qemu.nix;
    };
}
