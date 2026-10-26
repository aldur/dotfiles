# Graphical appliances

Run commands from the repository root. Set `guest` to the image name:

```bash
guest=NAME
```

## ChromeOS Baguette

Build on ARM Linux:

```bash
nix build "path:./base_hosts/$guest#baguette-zimage" \
  --override-input aldur-dotfiles path:.
```

Alternatively, select the image in **Build Baguette image**. Verify the artifact
before use:

```bash
gh run download --repo aldur/dotfiles --name "$guest-baguette-arm64"
gh attestation verify baguette_rootfs.img.zst --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/baguette-image.yml
gh attestation verify baguette_state.img.zst --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/baguette-image.yml
```

Decompress the verified base before use. The ARM64 disk sandbox in ChromeOS
156 blocks `pread64`, which crosvm uses to read compressed images:

```bash
zstd --decompress --keep baguette_rootfs.img.zst
```

Put `baguette_rootfs.img` and `baguette_state.img.zst` in ChromeOS
`Downloads/NAME`. Use a separate folder for each VM. Open crosh (`Ctrl+Alt+T`).
Replace `NAME` with the VM name:

```text
vmc create --vm-type BAGUETTE --size 12G \
  --source /home/chronos/user/MyFiles/Downloads/NAME/baguette_state.img.zst \
  NAME
vmc start --vm-type BAGUETTE \
  --rootfs /home/chronos/user/MyFiles/Downloads/NAME/baguette_rootfs.img \
  NAME
vsh NAME penguin
```

Start the VM with this command before using its app launcher entry. Repeat
the command after each VM stop or ChromeOS login. The app launcher does not
retain `--rootfs`. Do not use it to start a stopped VM.
Guest root can make the state disk bootable. A start without `--rootfs`
can then run code from that disk.

ChromeOS attaches the base image read-only. The separate VM disk holds
`/state`. Keep the base image outside all folders shared with Linux.
Use a new VM for this layout. Select the state disk size at creation.
Do not use ChromeOS disk resizing: it assumes the state disk is `/dev/vdb`,
but this layout puts it at `/dev/vdc`.

ChromeOS controls the kernel, display, input and clipboard. The VM boundary
requires a trusted, updated host. Do not share ChromeOS folders with the VM.

## QEMU

On Linux or Apple Silicon macOS:

```bash
nix run "path:./base_hosts/$guest#$guest-vm" \
  --override-input aldur-dotfiles path:. -- --gui
```

The launcher requires KVM on Linux or HVF on macOS. An ARM Linux builder or
cached build is required to build the guest on macOS.

The disk is `~/.local/share/NAME-vm/nixos.qcow2`. Use `--dir PATH` for another
instance. `--ephemeral` discards disk changes. `--clean` deletes the disk.
The default configuration has no shared folders, forwarded ports or clipboard.
The launcher supplies no audio device or microphone.

## State and updates

At each start, the VM uses a new root from the image. Only selected directories
are kept under `/state`. All other writes use RAM. Files and downloads outside
these directories are lost after a restart. The machine ID changes at each
start. The home directory has mode `0700`. Swap, core dumps, SSH and sudo are
disabled.

Close the app before stopping the VM. For QEMU, connect to the printed monitor
socket with `nc -U SOCKET`, issue `system_powerdown`, and wait for QEMU to exit.
For Baguette, stop the VM through ChromeOS.

Encrypt your backups. For QEMU, save the stopped disk and its launcher Nix
closure. The disk contains `/state`. The closure contains the kernel, initrd
and store image. For Baguette, save the stopped VM disk and its base image.
Restore on the same guest architecture. Never start two copies of one disk.

These appliances are not upgraded in place. Dependabot proposes input updates
on the 1st and 15th of each month. CI builds and tests the changes. After
the updates are merged, build a new image and create a new VM. Do this twice
a month and after urgent security fixes. A VM you keep runs old software.
A restart does not update it.

Use a new VM name on Baguette or a new `--dir` on QEMU. Start with empty state
and set up the app again. Data is not migrated from the old VM. A restored
backup also runs the software from that backup.

Read `/etc/appliance-release` for the resolved build inputs and their source
date. CI attests the image and the `inputs.json` file together.

## Tests

On x86-64 Linux with KVM:

```bash
nix build "path:./base_hosts/$guest#checks.x86_64-linux.qemu-boot" \
  "path:./base_hosts/$guest#checks.x86_64-linux.baguette-boot" \
  --override-input aldur-dotfiles path:.
```

The Baguette test boots the distributed image with crosvm and a Termina kernel.
Its host services are test fixtures. Test ChromeOS registration and host display
integration on the target Chromebook.
The test uses x86-64 with the crosvm sandbox disabled. It does not check the
ARM64 host disk policy.

QEMU tests use the same store-image builder with plain LZ4. Shipped images use
LZ4HC level 12.
