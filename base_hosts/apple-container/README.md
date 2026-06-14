# Apple `container` image

This Flake builds a NixOS OCI image that allows running [Apple `container`][0]
on Apple silicon:

| With | Entry point | What |
|---|---|---|
| `container run` | the OCI Entrypoint → syntetic activation → `fish` | an ephemeral container, doesn't mount `~` |
| `container machine` | `/sbin/init` → `systemd` | a persistent Linux box |

## Run from GHCR

CI publishes images to GHCR, so there's no need to build locally:

```bash
container run -it --rm ghcr.io/aldur/aldur-nixos:latest

container machine create ghcr.io/aldur/aldur-nixos:latest --name dev --home-mount none
container machine run -n dev
```

`ghcr.io/aldur/nixos:latest` is a minimal image.

Both images are multi-arch, so they'll pull the correct runtime for your
machine architecture.

## Build

Building on macOS requires a Linux builder (this repo's `nix-darwin` host
already provides one via `modules/darwin/linux-builder.nix` +
`nix-rosetta-builder`).

```bash
# build + load in one step:
nix run --override-input aldur-dotfiles . ./base_hosts/apple-container#load
```

Or : `nix build …#container-image`, then `container image load --input
./result`.

The archive sets its `org.opencontainers.image.ref.name` to
`aldur-nixos:latest` so it loads under that name directly.

> [!TIP]
> There's also a `minimal-image` that doesn't include this repo's
> configuration (`#load-minimal` builds and loads it).
> Once built, its name is just `nixos`.

### `container run`

```bash
container run -it --rm aldur-nixos:latest
```

### `container machine`

```bash
container machine create aldur-nixos:latest --name dev --home-mount none
container machine run -n dev          # boots systemd, opens a shell as your user
```

> [!WARNING]
> By default a machine mounts your **entire macOS home read-write** at
> `/Users/<you>` (and forwards your SSH agent socket). Use `--home-mount none`
> to disable it or make it the default with:

```toml
# ~/Library/Application Support/com.apple.container/config/config.toml
[machine]
home-mount = "none"
```

The agent forwarding has no flag, but the CLI lifts `SSH_AUTH_SOCK` from its
own environment on every boot (`container run` does too). Unset it to disable
forwarding:

```bash
env -u SSH_AUTH_SOCK container machine run -n dev
```

## Notes

- **A nix-daemon runs under `container run`** so that `nix` works inside the
  container. Under `container machine`, `systemd` runs the daemon normally.
- If you need `root`, you can use `container exec --user 0` or `container
  machine run --root`.
- **Logs & debugging:** the entrypoint writes to `/var/log/entrypoint/`
  (`nix-daemon.log`, `system-activation.log`, `home-manager.log`) and prints a
  red banner + log tail when a step fails. Run with `CONTAINER_DEBUG=1` in the
  environment to also dump the tty state before the shell hand-off.
- **DNS:** `container machine`'s bootstrap writes `/etc/resolv.conf` /
  `/etc/hosts` before the guest boots, so the image ships placeholder files (so
  `/etc` is a writable target) and disables the guest's DHCP/resolvconf.
- **Hostname:** under `container run` the entrypoint applies
  `networking.hostName` itself (the runtime otherwise names the container after
  its UUID). Under `container machine` the runtime first sets the machine's
  name (e.g. `dev`) and systemd applies `networking.hostName` during boot — a
  shell that opened early may keep showing the old name (fish caches it at
  startup).
- **No ICMP:** `ping` from inside shows 100% loss while TCP/UDP (DNS, HTTPS)
  work — Apple's vmnet NAT doesn't forward ICMP echo
  ([apple/container#345][1]); under `container run` there's additionally no
  `cap_net_raw`/setuid wrapper. Not fixable image-side.

[0]: https://github.com/apple/container
[1]: https://github.com/apple/container/issues/345
