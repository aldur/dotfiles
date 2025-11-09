# `qemu` VM guest

This Flake allows creating a NixOS, QEMU VM with the modules of this repository.

## Quick Start with Home Manager Module

If you have the `programs.qemu-vm` home manager module enabled, you can use the
`qemu-vm` CLI:

```bash
# Start VM with SSH forwarded to localhost:2222
qemu-vm -p 22:2222

# Start VM with custom location and multiple ports
qemu-vm -d /data/my-vm -p 22:2222 -p 80:8080

# Use a custom flake for VM configuration
qemu-vm --flake ~/my-custom-vm-flake -p 22:2222

# Rebuild and start with more resources
qemu-vm --build --memory 8192 --cores 4 --disk-size 128 -p 22:2222

# Show all options
qemu-vm --help
```

Enable the module in your home manager configuration:

```nix
programs.qemu-vm = {
  enable = true;
  # Optional: customize defaults
  defaultMemory = 4096;  # MB
  defaultCores = 4;
  defaultDiskSize = 64;  # GB
};
```

## Using a Custom Flake

You can point to any flake that provides a `nixosConfigurations.qemu-nixos` output. For example, you could copy this directory and modify `qemu.nix` with your customizations, then:

```bash
qemu-vm --flake ~/my-custom-vm -p 22:2222
```

## Flake usage

To run using the flake, use `nix run`:

```bash
nix run .
```

If you want to run it against a full repository clone:

```bash
nix run --override-input aldur-dotfiles ../../ .
```

## `hostPkgs`

Thanks to [`hostPkgs`][0], the VM host can be either Linux or macOS (through
[`nix-rosetta-builder`][1]).

## SSH keys

### Guest

The keys you'll find in this folder are only used within the `qemu` VM, which
is not exposed to the network but just to the host. Having them hard-coded
avoids needing to re-verify the guest fingerprint for every new VM.

[0]: https://github.com/NixOS/nixpkgs/blob/554be6495561ff07b6c724047bdd7e0716aa7b46/nixos/modules/virtualisation/qemu-vm.nix#L25
[1]: https://github.com/cpick/nix-rosetta-builder
