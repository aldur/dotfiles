# Graphical appliances

Run commands from the repository root. Set `guest` to the image name:

```bash
guest=NAME
```

## ChromeOS Baguette

Build on ARM Linux:

```bash
nix build "path:./base_hosts/$guest#baguette-zimage" --override-input aldur-dotfiles path:.
```

Alternatively, select the image in **Build Baguette image**. Verify the artifact
before use:

```bash
gh run download --repo aldur/dotfiles --name "$guest-baguette-arm64"
gh attestation verify baguette_rootfs.img.zst --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/baguette-image.yml
```

Put the image in ChromeOS Downloads. Open crosh (`Ctrl+Alt+T`). Replace `NAME`
with the VM name:

```text
vmc create --vm-type BAGUETTE --size 12G --source /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img.zst NAME
vmc start --vm-type BAGUETTE NAME
vsh NAME penguin
```

Start the app from its ChromeOS launcher entry or the guest shell.

ChromeOS controls the kernel, display, input and clipboard. The VM boundary
requires a trusted, updated host. Do not share ChromeOS folders with the VM.

## QEMU

On Linux or Apple Silicon macOS:

```bash
nix run "path:./base_hosts/$guest#$guest-vm" --override-input aldur-dotfiles path:. -- --gui
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
and store image. For Baguette, save the stopped VM disk.
Restore on the same guest architecture. Never start two copies of one disk.

VMs are never upgraded in place. Dependabot proposes input updates on the 1st
and 15th of each month. CI builds and tests the changes. After the updates are
merged, build a new image and create a new VM. Do this twice a month and after
urgent security fixes. A VM you keep runs old software. A restart does not
update it.

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

QEMU tests use the same store-image builder with plain LZ4. Shipped images use
LZ4HC level 12.
