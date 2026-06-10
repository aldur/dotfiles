# Apple `container` image

This Flake builds a NixOS OCI image with the modules of this repository, meant to
run as a lightweight, single-process container under [Apple `container`][0] on
Apple silicon.

Unlike the `qemu`/`crostini` hosts there is no systemd PID 1: Apple `container`
runs the image's entrypoint as a single process inside a per-container VM. The
entrypoint applies the NixOS + home-manager configuration at start (system
activation, then home-manager activation for `aldur`) and drops into a
configured `fish` login shell.

The whole environment is reused from `aldur-dotfiles.nixosModules.default` — no
packages or shell config are re-listed here.

## Build

The image targets `aarch64-linux` (Apple silicon). On macOS this requires a
Linux builder (this repo's `nix-darwin` host already provides one via
`modules/darwin/linux-builder.nix` + `nix-rosetta-builder`).

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#container-image
# → ./result  (a gzipped `docker save`-format OCI archive)
```

## Load & run

```bash
container image load --input ./result
container run -it aldur-nixos:latest
```

`container run -it aldur-nixos:latest <cmd>` still runs activation first, then
`<cmd>`.

### If `container image load` rejects the archive

Some `container` versions reject archives whose index omits a `mediaType`.
Normalize to an OCI archive with `skopeo` (in nixpkgs, no extra Flake input):

```bash
nix run nixpkgs#skopeo -- copy docker-archive:./result oci-archive:aldur-nixos.tar:latest
container image load --input ./aldur-nixos.tar
```

## Notes

- **No nix-daemon.** With no systemd PID 1 there is no `nix-daemon`, so the
  toolset is effectively immutable: everything baked into the image works (it is
  all on `PATH` via `/run/current-system/sw` and `/etc/profiles/per-user/aldur`),
  but `nix`/`nix-shell`/`nh`/`pyshell` and rebuilding do **not** work inside the
  container. To change the environment, edit `apple-container.nix` and rebuild
  the image. (If you need a daemon and full service management, that is the
  `container machine` / systemd path instead.)
- The entrypoint applies the configuration at start: NixOS system activation,
  then home-manager activation (`--driver-version 1`, after creating the per-user
  Nix profile dir it expects) — both run daemonless.
- No SSH host keys are checked in (unlike `qemu`/`crostini`): there is no `sshd`
  in this single-process container.
- To customize, edit `apple-container.nix` and rebuild.

[0]: https://github.com/apple/container
