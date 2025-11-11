# `qemu` VM guest

This Flake provides a pre-built NixOS QEMU VM with the modules from this
repository.

## Quick Start

The `qemu-vm` package provides a pre-built NixOS VM:

```bash
# Install or run the qemu-vm package
nix run github:aldur/dotfiles?dir=nix#qemu-vm -- -p 22:2222

# Or if you have it installed
qemu-vm -p 22:2222
```

### Examples

```bash
# Start VM with SSH forwarded to localhost:2222
qemu-vm -p 22:2222

# Start VM with custom location and multiple ports
qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

# Start with more resources
qemu-vm --memory 8192 --cores 4 --disk-size 128 -p 22:2222

# Run in snapshot mode (changes not saved to disk)
qemu-vm --snapshot -p 22:2222

# Clean VM state and start fresh
qemu-vm --clean -p 22:2222

# Enable GUI mode
qemu-vm --gui -p 22:2222

# Show all options
qemu-vm --help
```

## Cross-Platform Support

Thanks to [`hostPkgs`][0], the VM host can be either Linux or macOS (through
[`nix-rosetta-builder`][1]).

## SSH Keys

The SSH keys in this folder are only used within the `qemu` VM, which is not
exposed to the network but just to the host. Having them hard-coded avoids
needing to re-verify the guest fingerprint for every new VM.

## Development

To modify the VM configuration, edit `qemu.nix` and rebuild the package:

```bash
# From the nix directory
nix build .#qemu-vm
./result/bin/qemu-vm -p 22:2222
```

The VM configuration is built as part of the package derivation in
`/nix/packages/qemu-vm/qemu-vm.nix`.

[0]: https://github.com/NixOS/nixpkgs/blob/554be6495561ff07b6c724047bdd7e0716aa7b46/nixos/modules/virtualisation/qemu-vm.nix#L25
[1]: https://github.com/cpick/nix-rosetta-builder
