# macOS VMs

```sh
nix run .#macos-vm
```

On an Apple Silicon Mac, this downloads a pinned prepared macOS Tahoe image,
boots it headlessly, installs Nix, transfers the locally built nix-darwin system,
and activates it with Home Manager. No Setup Assistant, passwords, Nix commands
inside the VM, or manual configuration are required. The launcher prints `Ready`
only after checking the active system and guest tools. First boot downloads
about 27 GB of compressed macOS data plus the Nix dependencies.

The guest imports the actual [macOS configuration](../../base_hosts/macos/macos.nix)
and [shared Darwin modules](../../modules/darwin/configuration.nix), with
[VM overrides](../../base_hosts/macos/vm.nix). Your Fish, Git, tmux, LazyVim,
Codex, Claude Code, and other configured packages/settings are applied to the
prepared image's `admin` account (UID 501). Touch ID and the YubiKey agent are
disabled, and Remote Login is enabled. Personal credentials are not copied;
tools that need authentication still need their own credentials.

The Darwin-only dependencies and guest builder are encapsulated in
[`flake.nix`](flake.nix). The root flake only wires in the `macos-vm` input,
sharing its existing nixpkgs pins; it does not export a Darwin configuration.

```sh
# In another terminal, connect using the automatically generated VM identity
nix run .#macos-vm -- --ssh

# Inspect the guest's IP, verify its configuration, or stop it
nix run .#macos-vm -- --ip
nix run .#macos-vm -- --check
nix run .#macos-vm -- --stop

# Open a window instead of running headlessly
nix run .#macos-vm -- --gui

# Independent guest with more resources
nix run .#macos-vm -- --name testing --memory 16384 --cores 8 --disk-size 128
```

Defaults are 8 GB RAM, 4 CPUs, and a minimum 64 GB virtual disk. Existing disks
are never shrunk. The APFS container is expanded during provisioning. Changes
persist across restarts; rebuilding the launcher with a new guest configuration
automatically applies that system on the next launch. An unchanged system is
checked and reused. Shut down inside macOS for a clean shutdown; `--stop` stops
the VM from the host.

Restart by shutting down and launching again. In testing, Tart 2.36.0 lost its
guest-agent control socket after an in-guest warm reboot; stopping and starting
Tart restores access. Provisioning uses shutdown-and-start when APFS expansion
needs a restart, so that recovery step is unattended too.

State and image cache live in `~/.local/share/macos-vm`; override with `--dir`.
Use the same `--dir` and `--name` for management commands. Each guest has a
private SSH identity and known-hosts file under `.macos-vm-NAME/`. Host SSH
identities and agents are not used. Tart's guest agent installs the VM identity;
SSH travels through the VM socket transport, avoiding host local-network
permission prompts. Activated SSH policy requires public keys.
The image's local console account remains `admin` / `admin`.

Tart uses Apple's Virtualization framework and shared NAT networking. The guest
can reach the host and LAN; it does not have the QEMU launcher's network
isolation. No host directories are shared. Audio and clipboard sharing are off;
`--clipboard` opts into clipboard sharing. This is a persistent VM, without
QEMU's ephemeral mode or port forwarding.

`--image` selects another local or OCI Tart image for a new guest. It must be a
prepared Apple Silicon macOS guest with the Tart guest agent, Remote Login,
an `admin` account and passwordless sudo. The default image is pinned by digest in `launcher.sh`.
Raw IPSW installation is not part of the unattended workflow.

The flake supplies Tart (FSL license); Homebrew is not required. To install the
launcher through this repository's Home Manager configuration:

```nix
programs.macos-vm.enable = true;
```

In the host configuration, also allow Tart with
`nixpkgs.allowUnfreeByName = [ "tart" ];`. The Home Manager options
`defaultVmDir`, `defaultMemory`, `defaultCores`, and `defaultDiskSize` customize
the defaults.

## Testing

Fast argument validation and failure handling checks:

```sh
nix build .#checks.aarch64-darwin.macos-vm
```

Actual unattended first boot, provisioning, repeated activation, clean shutdown,
cold boot, and persistent guest data:

```sh
nix run .#macos-vm-e2e
```

The test uses a fresh VM name and retains the stopped VM and both boot logs for
inspection. It needs the hypervisor and network, so it is not a sandboxed Nix
build check. After a forced launcher termination, verify the VM is stopped
before removing a stale `.macos-vm-NAME/lock` directory.
