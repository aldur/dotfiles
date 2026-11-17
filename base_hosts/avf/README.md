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

The workflow `avf-image.yml` of the dotfiles builds the image on demand
(`workflow_dispatch`) and keeps it as the artifact `avf-arm64` for a few days.
The workflow attests the image. Download and verify it:

```bash
gh run download --repo aldur/dotfiles --name avf-arm64
gh attestation verify avf_image.tar.gz --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/avf-image.yml
```

`--predicate-type https://spdx.dev/Document` selects the SBOM instead.
`nix run ./base_hosts/avf#sbom-avf -- ./sbom` writes the same SBOM for a local
build.

## Install

1. Enable Settings > System > Developer options > Linux development
   environment. Open Terminal and let it install the default Debian guest.
2. Extract the image (`result` for a local build) and copy it to the Download
   folder of the phone:

   ```bash
   mkdir image && tar xzf avf_image.tar.gz -C image
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
