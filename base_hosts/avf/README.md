# Android Terminal (AVF) guest

This Flake builds a NixOS image for the Android Terminal app with the modules
of this repository plus [nixos-avf][0]. The installation needs no root, no
unlocked bootloader and no debuggable build.

## Build

The image is for arm64. Build on an aarch64 builder:

```bash
nix build ./base_hosts/avf#avf-image
```

KVM is not necessary: without it, qemu emulates the VM that installs the boot
loader.

## Install

1. Enable Settings > System > Developer options > Linux development
   environment. Open Terminal and let it install the default Debian guest.
2. Extract the image and copy it to the Download folder of the phone:

   ```bash
   mkdir image && tar xzf result -C image
   adb push image /sdcard/Download/
   ```

3. In Terminal, run `bash /mnt/shared/Download/image/replace.sh` (or
   `/mnt/shared/image/replace.sh`). The guest restarts. Open Terminal again:
   the second step starts automatically and restarts the guest again.

## Rebuild

From within the guest:

```bash
sudo nixos-rebuild switch --flake github:aldur/dotfiles?dir=base_hosts/avf#avf-nixos
```

If the phone has little free memory, run `nixos-rebuild dry-build` first.

[0]: https://github.com/nix-community/nixos-avf
