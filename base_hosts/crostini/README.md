# ChromeOS Crostini guest

This Flake allows creating a NixOS guest (LXC container or Baguette image) with
the modules of this repository plus [what it takes][0] to run in [ChromeOS
Crostini][1].

## SSH keys

### Guest

The keys you'll find in this folder are only used within the container/VM,
which is not exposed to the network but just to the host. Having them
hard-coded avoids needing to re-verify the guest fingerprint for every new
container instantiation.

[0]: https://aldur.blog/articles/2025/06/19/nixos-in-crostini
[1]: https://github.com/aldur/nixos-crostini/tree/main
