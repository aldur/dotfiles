# Graphical appliances

Run commands from the repository root. Select the image:

```bash
guest=signal # or browser
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
with `signal` or `browser`:

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

The home directory persists with mode `0700`. Temporary files and system logs
are volatile. Swap, core dumps, SSH and sudo are disabled.

Close the app before stopping the VM. For QEMU, connect to the printed monitor
socket with `nc -U SOCKET`, issue `system_powerdown`, and wait for QEMU to exit.
For Baguette, stop the VM through ChromeOS.

Keep backups encrypted. A QEMU backup needs the stopped disk and its launcher
Nix closure. The kernel, initrd and store image are outside the writable disk.
Restore on the same guest architecture. Never start two copies of one disk.

Apps update through Nix builds. Each appliance pins its Crostini revision.
Other inputs use the root `flake.lock` through the `--override-input` argument.
Update those pins before rebuilding. For QEMU,
back up the stopped VM, then use the new launcher with the same `--dir`.
For Baguette, create a replacement VM under a new name. Keep the old VM until
migration is complete. A restored backup can contain an expired or vulnerable
app version.

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
