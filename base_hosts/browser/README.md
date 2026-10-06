# Browser VM

Following [autofirma-vm][0], `guest.nix` holds the browser and hardening shared
by both platforms. `baguette.nix` supplies ChromeOS integration; `desktop.nix`
supplies the QEMU desktop. Both reuse the dotfiles guest helpers, without
loading the development configuration. Firefox's normal sandbox, cookies and
site storage remain enabled. Extensions, Firefox Sync, telemetry and saved
passwords are disabled. Links stay in the guest browser. Neither guest has an
SSH server or sudo.

## QEMU

From the repository root on Linux or Apple Silicon macOS:

```bash
nix run path:./base_hosts/browser#browser-vm --override-input aldur-dotfiles path:. -- --gui
```

The existing `qemu-vm` launcher boots a minimal XFCE desktop, logs in the
unprivileged user and starts Firefox. It requires KVM on Linux or HVF on macOS;
building the ARM Linux guest on macOS needs a Linux builder or cached outputs.
The default flake package is this launcher; Baguette keeps its explicit target.

State persists in `~/.local/share/browser-vm/nixos.qcow2`. Use `--dir PATH` for
a separate instance or `--ephemeral` to discard a session's writes. There are
no shared host directories, forwarded ports or clipboard by default.
`--clipboard` opts into the existing launcher's clipboard support (Cocoa on
macOS; the packaged GTK display on Linux does not support it).
The launcher currently has no virtual audio device, so guest audio playback
and microphone input are unavailable.

Close Firefox before stopping the VM. The launcher prints the QEMU monitor
socket; connect with `nc -U SOCKET` and issue `system_powerdown`, then wait for
QEMU to exit before copying the disk. `--clean` deletes that disk, including
the browser profile and downloaded files.

For a complete offline backup, retain the matching launcher Nix closure as well
as `nixos.qcow2`. The kernel, initrd and read-only store image are outside the
writable disk. A disk copy alone is not a self-contained VM export. Restore on
the same guest architecture with the original VM stopped. To update, build a
newer launcher and use the same `--dir`; take a stopped backup first. The new
launcher supplies the updated system while the home persists.

## Baguette

Build from the repository root on an ARM Linux builder:

```bash
nix build ./base_hosts/browser#baguette-zimage --override-input aldur-dotfiles .
```

Alternatively, select `browser` in the existing **Build Baguette image**
workflow. Download and verify its artifact:

```bash
gh run download --repo aldur/dotfiles --name browser-baguette-arm64
gh attestation verify baguette_rootfs.img.zst --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/baguette-image.yml
```

Put the image in ChromeOS Downloads. In crosh (`Ctrl+Alt+T`):

```text
vmc create --vm-type BAGUETTE --size 12G --source /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img.zst browser
vmc start --vm-type BAGUETTE browser
vsh browser penguin
```

Run `firefox` in that shell, or open Firefox from this VM's ChromeOS launcher
entry. ChromeOS controls the VM and provides its display and clipboard. This is
isolation from other guests, not protection from a compromised ChromeOS host or
browser session.

The home directory (including the entire Firefox profile) persists on the VM
disk with mode `0700`. Temporary files and logs are volatile; guest swap and
core dumps are disabled.

Firefox updates come through Nix builds; its built-in updater is disabled.
For Baguette, update the pinned dependencies and build a replacement image.
Create a new VM under a separate name and keep the old VM until any browser
data you need has been migrated and checked. An old backup also restores an
old browser version.

[0]: https://github.com/aldur/autofirma-vm
