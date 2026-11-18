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
  boot. It does shutdown, storage balloon, clipboard and port forwarding.
  As garcon in ChromeOS, it runs as the main user, with `NoNewPrivileges`.
  For each of shutdown and the TCP port monitor, a system unit does only
  that task (see `agent.nix`).
- Weston runs on the display of the app, with Xwayland. Programs started
  from the terminal show there. When GPU rendering is selected in the
  Terminal settings, OpenGL uses zink on the gfxstream Vulkan driver.
- The clipboard of the display synchronizes with Android.
- PipeWire plays and records through the virtio-snd card of the app.
- Android storage is at `/mnt/shared`.
- sudo does not work. Root logs in with `ssh root@.host`, through a Unix
  socket in the guest. The PIV key of a YubiKey signs through pcscd (see
  `smartcard.nix`), and ssh asks for its PIN.

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
On the phone, open the run in the browser and download `avf-arm64`. The
browser saves `avf-arm64.zip` in the Download folder. `install.sh` reads
the tarball from it.
`nix run ./base_hosts/avf#sbom-avf -- ./sbom` writes the same SBOM for a local
build.

## Tests

```bash
nix build ./base_hosts/avf#checks.x86_64-linux.avf-boot --override-input aldur-dotfiles .
```

This boots the image two times as the Terminal app does: with the kernel,
the initramfs and the kernel command line of the x86_64 Debian image of the
app (`tests/ferrochrome.nix`), with the devices of the app, and from a disk
as `install.sh` leaves it. On the cidata disk, `tests/probe.sh` stands in for
the agent. It runs as the agent and checks the terminal, the display, the
clipboard, sound, port forwarding, the storage balloon and the installation.
The checks `avf-agent`, `avf-display` and `avf-smartcard` of the root flake
test the modules.

The checks do not cover the Android side: the binder RPC of the real agent,
gfxstream, NFC and crosvm.

## Install

1. Enable Settings > System > Developer options > Linux development
   environment. Open Terminal and let it install the default Debian guest.
2. Make the disk larger in the Terminal settings, to 10 GB or more. Debian
   uses 1.6 GB and the extracted store about 2.8 GB. Then put the image in
   the Download folder of the phone: download the artifact (see above), or
   copy the tarball (for a local build,
   `result/tarball/nixos-terminal.tar.gz`):

   ```bash
   adb push avf_image.tar.gz /sdcard/Download/
   ```

3. In Terminal, get the install script and run it. It extracts the store
   and makes NixOS the init. The guest stops. Open Terminal again.

   ```bash
   curl -fLO https://raw.githubusercontent.com/aldur/dotfiles/master/base_hosts/avf/install.sh
   bash install.sh
   ```

   The first boot moves the Debian files to `/old-root`. Remove them when
   NixOS works: `ssh root@.host rm -rf /old-root`.

If NixOS does not boot, reset the guest to Debian in the Terminal settings.

## Rebuild

From within the guest:

```bash
ssh root@.host nixos-rebuild switch --flake github:aldur/dotfiles?dir=base_hosts/avf#avf-nixos
```

If the phone has little free memory, run `nixos-rebuild dry-build` first.

## Upgrade

To use a new image without a build on the phone, put it in the Download
folder (see [Build](#build)) and run:

```bash
ssh root@.host avf-upgrade
```

`avf-upgrade` extracts only the store paths that are missing and runs
`nixos-rebuild switch --store-path`. `--action boot` activates the system at
the next start. Images from before `avf-upgrade` do not have the system
link (`/nixos-system`) that it needs.

