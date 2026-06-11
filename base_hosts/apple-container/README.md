# Apple `container` image

This Flake builds a single NixOS OCI image, with the modules of this repository,
that serves **both** ways of running [Apple `container`][0] on Apple silicon —
the same closure with two entry doors:

| Run with | Entry point | Shape |
|---|---|---|
| `container run` | the OCI **Entrypoint** → activation → `fish` | lightweight, ephemeral container |
| `container machine` | the image's **`/sbin/init`** → **systemd** | full, persistent Linux box |

`container machine` ignores the OCI entrypoint and execs `/sbin/init`, so both
fit in one image. The whole environment is reused from
`aldur-dotfiles.nixosModules.default` — nothing is re-listed.

## Build

The image targets `aarch64-linux` (Apple silicon). On macOS this requires a
Linux builder (this repo's `nix-darwin` host already provides one via
`modules/darwin/linux-builder.nix` + `nix-rosetta-builder`). The package name
resolves on a Darwin host too (it maps to `aarch64-linux` and offloads).

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#container-image
container image load --input ./result
```

The archive sets its `org.opencontainers.image.ref.name` to `aldur-nixos:latest`
so it loads under that name directly.

## Run it (`container run`)

```bash
container run -it --rm aldur-nixos:latest
```

The entrypoint applies the config (starts a nix-daemon, system + home-manager
activation), then drops to `aldur`'s `fish` via plain `runuser` — which keeps the
controlling terminal the runtime gives PID 1, so the config (`lv`, the greeting,
conf.d) loads and the session stays responsive.

## Machine it (`container machine`)

```bash
container machine create aldur-nixos:latest --name dev
container machine run -n dev          # boots systemd, opens a shell as your user
```

A machine **clones the image's rootfs at `create` time** — after loading a new
image, `container machine rm dev` and re-`create`, or you keep booting the old
rootfs.

`container machine`'s real PID 1 is Apple's `/sbin.machine/init`, a `#!/bin/sh`
script virtiofs-mounted from the host that ends in `exec /sbin/init`. To host
it, the image ships a small FHS shim set (`/bin/sh`, `id`, `grep`, `cut`,
`chown` in `/bin` and `/usr/bin`), `/etc/os-release`, and a no-op
`/etc/machine/create-user.sh` (NixOS already declares the user) — without
these, boot dies with `failed to exec [/sbin.machine/init] … No such file or
directory` (the missing-shebang-interpreter ENOENT).

## Notes

- **A nix-daemon runs under `container run`** (the entrypoint starts it, image
  built with `includeNixDB`): home-manager activation needs it, and `nix` works
  inside. Under `container machine`, systemd runs the daemon normally.
- **Logs & debugging:** the entrypoint writes to `/var/log/entrypoint/`
  (`nix-daemon.log`, `system-activation.log`, `home-manager.log`) and prints a
  red banner + log tail when a step fails. Run with `CONTAINER_DEBUG=1` in the
  environment to also dump the tty state before the shell hand-off.
- **DNS:** `container machine`'s bootstrap writes `/etc/resolv.conf` /
  `/etc/hosts` before the guest boots, so the image ships placeholder files (so
  `/etc` is a writable target) and disables the guest's DHCP/resolvconf.
- No SSH host keys are checked in.
- To customize, edit `common.nix` (shared) or `apple-container.nix` (the image),
  and rebuild.

[0]: https://github.com/apple/container
