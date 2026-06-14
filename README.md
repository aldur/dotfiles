# Dotfiles

My collection of dotfiles:

- [`flake.nix`](./flake.nix) is the entrypoint, while directories hold
  modules, overlays, packages, etc.
- Host-specific configuration to into [`base_hosts`](base_hosts/), consuming
  the root [flake.nix](flake.nix) as an input.

Most modules assume the username to be `aldur`.

## Containers

The whole NixOS configuration ships as an OCI container, built in CI. Try it
out as follows.

On [Apple container][1]:

```bash
container run -it --rm ghcr.io/aldur/aldur-nixos:latest
# add --ssh to enable agent forwarding
```

With Docker/Podman [^apple-container]:

[^apple-container]: The images are optimized for Apple `container`, but I have
  successfully tested them on `podman` as well. Let me know if you encounter
  any issue!

```bash
podman run --rm -it ghcr.io/aldur/aldur-nixos:latest
```

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

### Everything else

Use `nix flake show github:aldur/dotfiles` for a full list. Some of my
favorites are `claude-log`, `flatten-pdf`, `shrink-pdf`, and `llm`.

## Templates

### QEMU VM

To further configure the QEMU VM, clone the template:

```bash
nix flake init --template github:aldur/dotfiles#vm-nogui
```

### Apple `container`

To build a NixOS OCI image for [Apple `container`][1], clone the template:

```bash
nix flake init --template github:aldur/dotfiles#apple-container
```

See [the README](base_hosts/apple-container/README.md) for how to build, load,
and run it.

[0]: https://www.lazyvim.org
[1]: https://github.com/apple/container
