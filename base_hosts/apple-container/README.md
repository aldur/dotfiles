# Apple `container` images

This Flake builds NixOS OCI images with the modules of this repository, to run
under [Apple `container`][0] on Apple silicon. There are two flavours, sharing
the same environment (`common.nix`) but differing in how they boot:

| Image | Run with | PID 1 | Shape |
|---|---|---|---|
| `container-image` | `container run` | the entrypoint (one process) | lightweight, ephemeral container |
| `machine-image` | `container machine` | the image's `/sbin/init` → **systemd** | full, persistent Linux box |

Both reuse `aldur-dotfiles.nixosModules.default`.

## Build

The images target `aarch64-linux` (Apple silicon). On macOS this requires a
Linux builder (this repo's `nix-darwin` host already provides one via
`modules/darwin/linux-builder.nix` + `nix-rosetta-builder`).

```bash
# lightweight `container run` image
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#container-image

# full `container machine` image
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#machine-image
```

Each builds an OCI archive at `./result`. The archive sets its
`org.opencontainers.image.ref.name` so it loads under the right name directly.

## `container-image` (`container run`)

There is no systemd: Apple runs the image's entrypoint as a single process. The
entrypoint applies the config at start (starts a nix-daemon, runs system
activation, then home-manager activation for `aldur`) and drops into a `fish`
login shell.

```bash
container image load --input ./result
container run -it --rm aldur-nixos:latest
```

`container run -it aldur-nixos:latest <cmd>` still runs activation first, then
`<cmd>`.

## `machine-image` (`container machine`)

Apple execs the image's `/sbin/init` (the NixOS stage-2 init → systemd as PID
1), so it behaves like a small persistent Linux box with real service
management.

```bash
container image load --input ./result
container machine create aldur-nixos-machine:latest --name dev
container machine run -n dev          # boots it, opens a shell as your user
```

[0]: https://github.com/apple/container
