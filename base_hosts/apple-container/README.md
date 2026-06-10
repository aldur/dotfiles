# Apple `container` images

This Flake builds NixOS OCI images with the modules of this repository, to run
under [Apple `container`][0] on Apple silicon. There are two flavours, sharing
the same environment (`common.nix`) but differing in how they boot:

| Image | Run with | PID 1 | Shape |
|---|---|---|---|
| `container-image` | `container run` | the entrypoint (one process) | lightweight, ephemeral container |
| `machine-image` | `container machine` | the image's `/sbin/init` → **systemd** | full, persistent Linux box |

Both reuse `aldur-dotfiles.nixosModules.default` — no packages or shell config
are re-listed here.

## Build

The images target `aarch64-linux` (Apple silicon). On macOS this requires a
Linux builder (this repo's `nix-darwin` host already provides one via
`modules/darwin/linux-builder.nix` + `nix-rosetta-builder`). The package names
resolve on a Darwin host too — they map to `aarch64-linux` and offload to the
builder.

```bash
# lightweight `container run` image
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#container-image

# full `container machine` image
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#machine-image
```

Each builds an OCI archive at `./result`. The archive sets its
`org.opencontainers.image.ref.name` so it loads under the right name directly;
if a `container` version parses that differently and the image shows up as
`latest`/`<none>` in `container image ls`, retag once with `container image tag`.

## `container-image` — lightweight (`container run`)

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

## `machine-image` — full system (`container machine`)

Apple execs the image's `/sbin/init` (the NixOS stage-2 init → systemd as
PID 1), so it behaves like a small persistent Linux box with real service
management — closest to the `qemu`/`crostini` hosts.

```bash
container image load --input ./result
container machine create aldur-nixos-machine:latest --name dev
container machine run -n dev          # boots it, opens a shell as your user
```

## Notes

- **`container-image` runs a nix-daemon.** With no systemd, the entrypoint
  starts `nix-daemon` itself, and the image is built with `includeNixDB` so the
  store paths are registered. This is required for home-manager activation (its
  gcroots call `nix-store --realise --add-root` against `NIX_REMOTE=daemon`),
  and as a bonus `nix`/`nix-shell`/`nh` work inside. It is still one
  `container run` — the daemon is a background helper, not systemd. The
  `machine-image` gets a real daemon and services from systemd instead.
- **`container-image` needs a controlling TTY**, so the entrypoint uses
  `runuser --pty` for interactive sessions; otherwise fish never sources its
  config (aliases like `lv`, the greeting, conf.d). `container machine` provides
  the tty itself.
- The `machine-image` assumes the `aldur` user (declared, `mutableUsers = false`).
  `container machine run` opens a shell matching your host username, so this
  fits a host user named `aldur`.
- **`machine-image` is unverified against Apple's runtime here** — its boot is
  built the same way nixos-containers/LXC boot systemd, but `container machine`
  could not be exercised on Linux. Watch the first boot for masked-unit or
  `/sbin/init` issues.
- No SSH host keys are checked in (unlike `qemu`/`crostini`).
- To customize, edit `common.nix` (shared), `apple-container.nix` (lightweight)
  or `apple-machine.nix` (full), and rebuild.

[0]: https://github.com/apple/container
