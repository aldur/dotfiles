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

The workflow `baguette-image.yml` of the dotfiles builds the arm64 image on
demand (`workflow_dispatch`, image `crostini`) and keeps it as the artifact
`crostini-baguette-arm64` for a few days. The workflow attests the image.
Verify the download and  `vmc create`:

```bash
gh run download --repo aldur/dotfiles --name crostini-baguette-arm64
gh attestation verify baguette_rootfs.img.zst --repo aldur/dotfiles \
  --signer-workflow aldur/dotfiles/.github/workflows/baguette-image.yml
```

`--predicate-type https://spdx.dev/Document` selects the SBOM instead.
`nix run .#sbom-baguette -- ./sbom` writes the same SBOM for a local build.

`nix flake check` boots the image of the same system in crosvm with
nixos-crostini's smoke harness. The shared guest module selects
`users.users.${config.mainUser}.crostini.enable = true`, letting upstream own boot-time lingering
and display-service ordering. Home persistence does not control registration.
The harness boots the distributed image through `/sbin/init` without
an initrd, observes the user manager before user commands, and never enables
lingering or changes device permissions. `tests/baguette-boot.nix` adds
filesystem, SSH, activation and daemon-build probes. The SSH fixture replaces
authorized keys, and the activation probe switches to the current generation.

The tools disk, graphics stack and host daemons are fixtures. These smoke
checks do not establish real ChromeOS registration or suspend/resume behavior;
use the [device procedure](tests/device-boot.md) for those. The separate
`baguette-verifier` check needs no KVM and rejects truncated logs, failed
probes, wrong kernels, missing resize, VM failures and timeouts.

```bash
nix build .#checks.x86_64-linux.baguette-boot -L
```

To test changes in both local repositories, run from the dotfiles root:

```bash
nix build ./base_hosts/crostini#checks.x86_64-linux.baguette-boot \
  --override-input aldur-dotfiles . \
  --override-input nixos-crostini "path:$HOME/nixos-crostini" \
  --no-write-lock-file -L
```

## SSH as `root`

SSH is for root administration **from inside the guest**. `ssh.nix` forces port
22 to bind to `127.0.0.1` and, when IPv6 is enabled, `::1`. Upstream Crostini
currently disables IPv6. The allowlist is just `root`. Only public-key
authentication is accepted, using the root-managed authorized keys configured
in `crostini.nix`.

## SSH validation

Run these from the **dotfiles repository root**. The explicit input
override makes the platform check use this checkout:

```bash
nix build .#checks.x86_64-linux.crostini-ssh -L
nix build ./base_hosts/crostini#checks.x86_64-linux.ssh-configurations \
  --override-input aldur-dotfiles . --no-write-lock-file -L
```

The first check boots two independent VMs using the production SSH policy,
with firewalls disabled, two external interfaces each, and IPv4/IPv6.
It checks successful root login on loopback, rejection of `aldur` even with
an authorized key, and refused TCP connections to every external address
from the guest and its peer. Ping provides a routing control. It also
checks distinct generated identities, rejection of a store-backed fixture key as
host identity, mode `0600`, and persistence through service restart and
reboot with a separate `/persist` disk and tmpfs `/home`.

The second check evaluates the complete LXC and Baguette configurations
and parses their rendered configuration with OpenSSH, including variants
without tmpfs `/home` and with IPv6 enabled. Both checks are available for
`aarch64-linux` as well. The VM check is included in the root flake checks.

These tests cover the guest policy, not ChromeOS's proprietary host
integration. On a deployed Chromebook, also verify `ss -ltn 'sport = :22'`
and `sshd -T` through the guest console. Root SSH to guest loopback must
succeed with an authorized key; `aldur` must be denied. For each guest
non-loopback IPv4/IPv6 address, test port 22 from the guest, ChromeOS, and
an available sibling guest or LAN peer with a working route: it must be
closed. Repeat after reboot and any ChromeOS forwarding changes, and
compare fingerprints across two independently initialized instances.
No live Chromebook is exercised by the automated checks.

[0]: https://aldur.blog/articles/2025/06/19/nixos-in-crostini
[1]: https://github.com/aldur/nixos-crostini/tree/main
