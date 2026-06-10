# Apple `container` image

This Flake builds a NixOS OCI image with the modules of this repository, meant to
run as a lightweight, single-process container under [Apple `container`][0] on
Apple silicon.

Unlike the `qemu`/`crostini` hosts there is no systemd PID 1: Apple `container`
runs the image's entrypoint as a single process inside a per-container VM. The
entrypoint applies the NixOS + home-manager configuration at start (starts a
nix-daemon, runs system activation, then home-manager activation for `aldur`)
and drops into a configured `fish` login shell.

The whole environment is reused from `aldur-dotfiles.nixosModules.default` — no
packages or shell config are re-listed here.

## Build

The image targets `aarch64-linux` (Apple silicon). On macOS this requires a
Linux builder (this repo's `nix-darwin` host already provides one via
`modules/darwin/linux-builder.nix` + `nix-rosetta-builder`).

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/apple-container#container-image
# → ./result  (a `docker save`-format archive)
```

## Convert, load & run

Apple `container image load` only accepts an **OCI archive**, while Nix produces
a `docker save`-format archive — so convert it first with `skopeo` (in nixpkgs,
no extra Flake input). This step runs on the host rather than inside the build,
because the OCI writer needs `/var/tmp`, which macOS has but the Nix sandbox does
not.

```bash
nix run nixpkgs#skopeo -- --insecure-policy copy \
  docker-archive:"$(readlink -f result)" \
  oci-archive:aldur-nixos.oci:latest

container image load --input ./aldur-nixos.oci
container image ls                       # note the name it loaded as
container run -it --rm aldur-nixos:latest
```

`container run -it aldur-nixos:latest <cmd>` still runs activation first, then
`<cmd>`.

### Image name after load

Converting through an OCI archive drops the repository name, so the image loads
as `NAME=latest, TAG=<none>`. Retag it once:

```bash
container image tag latest aldur-nixos:latest
container run -it --rm aldur-nixos:latest
```

## Notes

- **There is a nix-daemon.** With no systemd, the entrypoint starts
  `nix-daemon` itself, and the image is built with `includeNixDB` so the store
  paths are registered. This is required for home-manager activation (its
  gcroots call `nix-store --realise --add-root` against `NIX_REMOTE=daemon`),
  and as a bonus `nix`/`nix-shell`/`nh` work inside the container. It is still a
  single `container run` — the daemon is a background helper, not systemd. (For
  full service management, that is the `container machine` / systemd path.)
- The `specialfs` activation snippet prints `mount: … permission denied`
  warnings on start — it tries to mount `/proc`, `/dev`, … which the runtime
  already provides. These are benign; activation continues.
- No SSH host keys are checked in (unlike `qemu`/`crostini`): there is no `sshd`
  in this single-process container.
- To customize, edit `apple-container.nix` and rebuild.

[0]: https://github.com/apple/container
