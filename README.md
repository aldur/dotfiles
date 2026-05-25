# Dotfiles

My collection of dotfiles.

## Structure: `nix`

[`flake.nix`](./flake.nix) is the entrypoint, while directories hold modules,
overlays, packages, etc.

Host-specific configuration to into [`base_hosts`](base_hosts/), consuming
the root [flake.nix](flake.nix) as an input.

Most modules assume the username to be `aldur`.

## Packages

See the [`packages`](./packages/) directories for a few more.

### `lazyvim`

A slightly customized [LazyVim setup][0].

```bash
nix run "github:aldur/dotfiles#lazyvim"
```

Or its _light_ version:

```bash
nix run "github:aldur/dotfiles#lazyvim-light"
```

### `qemu-vm`

Launch a `qemu-vm` with the configuration from this repository.

See [the README](base_hosts/qemu/README.md) for more information.

```bash
nix run "github:aldur/dotfiles#qemu-vm"
```

## Templates

### QEMU VM

To further configure the QEMU VM, clone the template:

```bash
nix flake init --template github:aldur/dotfiles#vm-nogui
```

[0]: https://www.lazyvim.org
