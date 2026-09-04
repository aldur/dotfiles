# ChromeOS Crostini guest

This Flake allows creating a NixOS guest (LXC container or Baguette image) with
the modules of this repository plus [what it takes][0] to run in [ChromeOS
Crostini][1].

## Baguette

`crostini.nix` includes what both guests share. `baguette.nix` has what the
Baguette image adds: the disk size, and the size cuts. The image has no kernel
(Baguette boots the ChromeOS kernel) and no mesa (the sommelier of ChromeOS
brings its own libraries; programs render in software).

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
