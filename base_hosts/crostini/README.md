# ChromeOS Crostini guest

This Flake allows creating a NixOS guest (LXC container or Baguette image) with
the modules of this repository plus [what it takes][0] to run in [ChromeOS
Crostini][1].

## Baguette

`crostini.nix` includes what both guests share, size cuts included: no mesa
(the sommelier of ChromeOS brings its own libraries; programs render in
software), no `doc` outputs, no llm models, no difftastic, a GTK pinentry.
`baguette.nix` has the disk size of the image. The image has no kernel:
Baguette boots the ChromeOS kernel.

The workflow `baguette-image.yml` of the dotfiles builds the arm64 image
on demand (`workflow_dispatch`, image `crostini`) and keeps it as the
artifact `crostini-baguette-arm64` for a few days.

`nix flake check` boots the image of the same system in crosvm and probes
it, with `lib.mkBaguetteTest` of the dotfiles. See `utils/baguette-test.nix`
there for what it covers, and what it cannot.

```bash
nix build .#checks.x86_64-linux.baguette-boot -L
```

## SSH keys

### Guest

The keys you'll find in this folder are only used within the container/VM,
which is not exposed to the network but just to the host. Having them
hard-coded avoids needing to re-verify the guest fingerprint for every new
container instantiation.

[0]: https://aldur.blog/articles/2025/06/19/nixos-in-crostini
[1]: https://github.com/aldur/nixos-crostini/tree/main
