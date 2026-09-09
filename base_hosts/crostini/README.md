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

`nix flake check` boots the image of the same system in crosvm and probes
it, with `lib.mkBaguetteTest` of the dotfiles. See `utils/baguette-test.nix`
there for what it covers, and what it cannot. `tests/baguette-boot.nix` adds
the probes of this guest: the kernel refuses a module, `nosuid` and `nodev`
hold on the home and on the `/persist` binds, and sudo, the agent sandbox
and a daemon build still work. `baguette-boot-termina` is the same check
with the kernel that Baguette boots on ChromeOS, built from the ChromeOS
kernel tree by `utils/termina-kernel.nix` of the dotfiles. CI runs both on
x86_64 runners.

```bash
nix build .#checks.x86_64-linux.baguette-boot -L
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
checks distinct generated identities, rejection of a legacy store key as
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
