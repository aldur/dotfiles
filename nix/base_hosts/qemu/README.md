# `qemu` VM guest

This Flake allows creating a NixOS, QEMU VM with the modules of this repository.

To run, just use `nix run`.

If you want to run it it against a full repository clone:

```bash
nix run --override-input aldur-dotfiles ../../ .
```

## `hostPkgs`

Thanks to [`hostPkgs`][0], the VM host can be either Linux or macOS (through [`nix-rosetta-builder`][1]).

## SSH keys

### Guest

The keys you'll find in this folder are only used within the `qemu` VM, which
is not exposed to the network but just to the host. Having them hard-coded
avoids needing to re-verify the guest fingerprint for every new VM.

[0]: https://github.com/NixOS/nixpkgs/blob/554be6495561ff07b6c724047bdd7e0716aa7b46/nixos/modules/virtualisation/qemu-vm.nix#L25
[1]: https://github.com/cpick/nix-rosetta-builder
