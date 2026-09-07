# `qemu` VM guest

This Flake provides a pre-built NixOS QEMU VM with the modules from this
repository.

## Quick Start

The `qemu-vm` package provides a pre-built NixOS VM:

```bash
# Install or run the qemu-vm package
nix run github:aldur/dotfiles#qemu-vm -- -p 22:2222

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

# Share the clipboard with the guest (the guest must run spice-vdagent).
# Works with the Cocoa display on macOS; the GTK display on Linux has no
# clipboard support in the nixpkgs build.
qemu-vm --gui --clipboard -p 22:2222

# Expose a host file to the guest as /run/qemu-vm-files/notes.txt
qemu-vm --file notes.txt=~/notes.txt -p 22:2222

# No network device at all, and no gvproxy process
qemu-vm --no-network

# Show all options
qemu-vm --help
```

## Cross-Platform Support

Thanks to [`hostPkgs`][0], the VM host can be either Linux or macOS (through
[`nix-rosetta-builder`][1]).

## Network

[gvproxy][2] gives the guest its network. It runs next to QEMU as its own
process and does the NAT, the DHCP, the DNS, and the port forwards of `-p`.
QEMU only holds a unix socket to it, so it has no in-process SLiRP.

The guest has the address `192.168.127.2`. It cannot reach the host:
gvproxy refuses connections to loopback and to every address of the host,
maps no virtual IP to the host, serves no API to the guest, and binds the
`-p` forwards on loopback only (see the two `gvproxy-*.patch` files in
`overlays/overrides`). `--no-network` gives the guest no NIC at all and
starts no gvproxy.

On macOS, both QEMU and gvproxy run under `sandbox-exec` with
deny-by-default profiles
that list only what each process was seen to need: its own closure, the
kernel and initrd, the disk and store images, the sockets and files of
the run directory, and the files of `--file`. QEMU has no host network,
reads nothing under the home directory, and cannot spawn processes.
gvproxy dials no address of the host, reaches no unix socket but the
resolver, and binds only the `-p` forwards. `--gui` adds what the Cocoa
display needs; the GPU stays denied, so it renders in software.
`--no-sandbox` turns all of it off. On Linux hosts there is no equivalent
yet; the gvproxy patches still keep the host out of the guest's reach.

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
`/packages/qemu-vm/qemu-vm.nix`.

[0]: https://github.com/NixOS/nixpkgs/blob/554be6495561ff07b6c724047bdd7e0716aa7b46/nixos/modules/virtualisation/qemu-vm.nix#L25
[1]: https://github.com/cpick/nix-rosetta-builder
[2]: https://github.com/containers/gvisor-tap-vsock
