# Android Terminal (AVF) guest

This Flake builds a NixOS guest for the Android Terminal app with the modules
of this repository. It replaces the Debian guest in place. The installation
needs no root, no unlocked bootloader and no debuggable build. It works with
the Terminal of GrapheneOS.

The guest keeps the kernel of the app and the interface of the AOSP Debian
guest (`build/debian` in `platform/packages/modules/Virtualization`):

- The app boots its kernel with `root=/dev/vda1`. `/sbin/init` starts the
  current NixOS generation.
- ttyd listens on a Unix socket. socat connects it to vsock port 7681, where
  the app opens the terminal.
- `linux_vm_manager` comes from `cidata.iso` of the app (`/dev/vdb`) at each
  boot. It does shutdown, storage balloon and clipboard.
- Android storage is at `/mnt/shared`.

Port forwarding to Android does not work: the agent finds ports with
`tcpstates-libbpf`, which Nixpkgs does not package. Graphics are not set up.

## Build

The image is for arm64. Build on an aarch64 builder:

```bash
nix build ./base_hosts/avf#avf-image
```

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
2. Make the disk larger in the Terminal settings, to 8 GB or more. Debian
   uses 1.6 GB and the extracted store about 2 GB. Then copy the image (for a local build,
   `result/tarball/nixos-terminal.tar.gz`) and the install script to the
   Download folder of the phone:

   ```bash
   adb push avf_image.tar.gz base_hosts/avf/install.sh /sdcard/Download/
   ```

3. In Terminal, run `bash /mnt/shared/Download/install.sh`. It extracts the
   store and makes NixOS the init. The guest stops. Open Terminal again.
   The first boot moves the Debian files to `/old-root`. Remove them when
   NixOS works: `sudo rm -rf /old-root`.

If NixOS does not boot, reset the guest to Debian in the Terminal settings.

## Rebuild

From within the guest:

```bash
sudo nixos-rebuild switch --flake github:aldur/dotfiles?dir=base_hosts/avf#avf-nixos
```

If the phone has little free memory, run `nixos-rebuild dry-build` first.

