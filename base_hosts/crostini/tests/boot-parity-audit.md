# Baguette boot test audit

Audit date: 2026-09-11. This is a source and evaluated-configuration audit,
not a successful reproduction on ChromeOS. No runtime tests were run during
this audit: this environment has no `/dev/kvm`, and access to the affected
Chromebook has not been established.

The baseline checks described below do not reproduce the real Baguette boot. In particular,
they can repair the missing user session before asserting that user services
work. The shared `../baguette-guest.nix` now declares lingering, but the
current runtime checks do not establish that the guest starts unassisted.

Upstream references below use the resolved nixos-crostini revision
`06b6032cf16290c14c98301d9b5b1d34ad38b5ef`. Local references are relative to
this document. Findings about test substitutions describe coverage gaps;
they do not establish that every substituted component is broken.


Remediation is now implemented in the local shared `smoke.nix`, AutoFirma
probes, QEMU configuration comparison and CI wiring. The findings below
preserve the audited baseline. The new harness removes session/device
repairs, uses `/sbin/init` without an initrd, checks all user integration
units, propagates failures and runs the production Firefox wrapper plus
cryptographic signing. It still uses explicit host/graphics fixtures; see
[device-boot.md](device-boot.md) for the required ChromeOS validation.

## Findings

| Priority | Difference | Consequence and evidence |
| --- | --- | --- |
| High | The smoke probe enables lingering and makes the render node world writable. | Missing session bootstrap and device access configuration can pass. Failed system units are sampled before this intervention; the generic user check covers only `sommelier@0` and its socket. [Upstream probe](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-smoke.nix#L100). |
| High | Host integration daemons are replaced. | `vshd`, `garcon`, and `port_listener` sleep forever; fake `maitred` runs the probe. No real registration handshake, user provisioning, host network/time updates, shared folder setup, or shell connection is exercised. [Tools disk](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-smoke.nix#L159). |
| High | The kernel entry path differs. | Default smoke uses a NixOS kernel/initrd. Even its no-initrd Termina variant passes `init=<toplevel>/init`, bypassing the shipped `/sbin/init`. Inspecting that symlink after activation cannot establish that the kernel could use it before activation. [Boot invocation](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-smoke.nix#L258). |
| High | AutoFirma's Baguette check bypasses its session wrapper. | It creates a headless Firefox profile, initializes NSS, and imports the certificate directly from the probe disk. It injects `MOZ_LEGACY_HOME=1`. This misses launcher environment propagation, the real shared Downloads path, and password prompting. The production wrapper is `autofirma-vm-firefox`. [Probe](../../autofirma/flake.nix), [wrapper](../../autofirma/guest.nix), [shared files configuration](../../autofirma/baguette.nix). |
| High | A Java exception can satisfy the AutoFirma startup assertion. | `autofirma exit [0-9]* [1-9]` accepts any exit status, including failure or timeout, if the log contains `es.gob.afirma` or `java.awt`. This establishes some Java execution, not usable GUI, WebSocket readiness, or signing. [Assertion](../../autofirma/flake.nix). |
| High | CI does not execute the AutoFirma runtime checks. | CI builds its QEMU launchers and ARM Baguette system closure. It runs the regular Crostini x86 smoke checks, not AutoFirma's `baguette-boot` or `sign-via-websocket`. The image workflow builds and attests without booting. [CI](../../../.github/workflows/ci.yml), [image workflow](../../../.github/workflows/baguette-image.yml). |
| Medium | The Termina kernel is representative, not the device kernel. | The package builds 6.6.147 from a different commit; the supplied log runs ARM64 `6.6.135-09383-g1140e4f27e24`. AutoFirma uses the default smoke kernel. x86 CI cannot establish ARM sysctl compatibility. [Kernel package](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/packages/termina-kernel.nix). |
| Medium | Graphics and the tools filesystem differ. | Smoke constructs a btrfs tools disk with nixpkgs sommelier/Mesa and injected library paths plus `--virtgpu-channel`; the real log mounts an ext4 ChromeOS tools disk. Smoke has no Xwayland/host compositor coverage. The root disk is enlarged, and VM hardware/console arguments also differ. [Harness](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-smoke.nix). |
| Medium | crosvm failure does not necessarily fail smoke. | The failure handler prints the exit code, then resets `status=0` before checking probes. A failure or timeout after all successful probes can pass. The guest also uses forced shutdown. [Exit handling](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-smoke.nix#L280). |
| Medium | No real host suspend/resume coverage. | The reported watchdog aborts and RCU stalls occur around host suspend/resume. Boot or guest reboot probes do not reproduce that lifecycle. Neither harness supplies the actual host services that coordinate it. |

## Other tests and configuration differences

The upstream full [GUI/reboot test](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/tests/baguette-boot.nix)
uses `/sbin/init`, but supplies a synthetic initrd that installs probe units,
pre-mounts tools, and overlays extra Nix store paths. It simulates user setup,
enables lingering, relaxes render permissions, and explicitly starts/restarts
user managers and sommelier instances. Its ChromeOS daemons are stand-ins;
graphics use patched nixpkgs sommelier, Xwayland and headless Weston. This
provides component and reconfiguration coverage, not the real host boot
sequence. Dotfiles uses the smoke helper rather than this full test. Unlike
smoke, the full test does propagate crosvm failure.

The [regular Crostini probe](baguette-boot.nix) replaces root's authorized keys
with a fixture and switches to the already-running generation. Its SSH and
activation checks do not prove initial key provisioning or a rebuild to a
different generation. Its permission fixtures exercise explicit filesystem
policies after startup; they do not validate initial session bootstrap.

The [QEMU signing test](../../autofirma/tests/sign-via-websocket.nix) imports
the desktop and file-transfer modules but omits the shared QEMU guest module
used by the shipped configuration. Evaluating `sign-via-websocket.nodes.machine`
against `nixosConfigurations.autofirma-vm-x86_64.config`, with the local
dotfiles input override, confirmed these differences:

| Setting | Signing test | Shipped QEMU guest |
| --- | --- | --- |
| `virtualisation.useNixStoreImage` | false | true |
| Shared directories | `nix-store`, `shared`, `xchg` | none |
| Test backdoor service | present | absent |
| System/user start and device timeouts | test adds 300 seconds | test overrides absent |
| Logrotate | disabled | enabled |
| Homepage | `https://sede.test/` | bundled local page |
| Firefox derivation | test policy derivation | different production policy derivation |
| Local Caddy server | enabled | disabled |

Both evaluated configurations declare `MOZ_LEGACY_HOME=1`. The initial
comparison checked the unconfigured `programs.autofirma.package`; checking
`finalPackage` during remediation exposed another difference: the test CA
also changed AutoFirma's Java truststore and Firefox integration references.
The new comparison checks the final packages, and the HTTPS fixture's CA is
imported only into the test browser profile. The QEMU test validates a real signature and rejection of
tampered content. Its local CA/server, supplied certificate password, and
headless signing parameters are deliberate fixtures; password entry and
certificate selection UI remain outside that scenario. It does not establish
Baguette behavior.

The pcscd, PIV and SSH tests under this directory are component tests with
synthetic machines, keys/devices and selected production modules. The PIV
fixture supplies user lingering and scripted PIN entry. SSH configuration
checks evaluate real variants, but do not boot them. These tests retain value
within those scopes; none substitutes for ChromeOS USB attachment, session
creation, or full-image boot.

The original AutoFirma [README](../../autofirma/README.md) described the
default smoke as both booting without an initrd and using a test initrd.
The updated description matches the corrected harness and identifies its
remaining host fixtures.

## Upstream lifecycle contract

Recommended design: expose an explicit selected guest user in nixos-crostini
(for example, a new `crostini.user` option). Baguette should own that user's
boot-time user manager and ChromeOS service dependencies. Callers should not
need a separate lingering setting, nor should it depend on home persistence.

Declarative lingering is an appropriate implementation: systemd defines it
to start the user manager at boot and retain it after logout. See the
[systemd documentation](https://github.com/systemd/systemd/blob/main/man/loginctl.xml).
The module should validate the selected account and contradictory lifecycle
configuration. It should also define readiness and ordering for the ChromeOS
session: the current [garcon definition](https://github.com/aldur/nixos-crostini/blob/06b6032cf16290c14c98301d9b5b1d34ad38b5ef/common.nix#L197)
explicitly notes missing ordering after sommelier. Simply moving the existing
units to system services with `User=` would require rebuilding their user
bus, runtime directory and display environment integration.

## Required real boot validation

1. Record the exact ARM image checksum, resolved inputs, ChromeOS build,
   supplied kernel and tools disk identities, and host VM startup parameters.
   Test the distributable image artifact, not a separately generated root.
2. Cold-start a fresh guest using the real ChromeOS host path and its kernel
   entry through `/sbin/init`, without an added initrd, injected units/store
   overlay, replacement daemons, or manual device permission changes.
3. Observe registration and the selected user's manager and ChromeOS services
   **before any login**. No test may enable lingering, start a user manager,
   or manually start the services being asserted. A diagnostic login can
   itself conceal the bootstrap failure.
4. Require real `penguin` registration, shell access, both Wayland and X
   integration, and launcher execution with the production environment.
   Share Downloads through ChromeOS, import a synthetic test certificate
   through the production wrapper, and verify an actual signature. Exercise
   the password-file and interactive-password paths separately.
5. Exercise a normal stop/start and host suspend/resume. Collect pre-login
   serial/host logs, service failures and restart counts, and check for the
   reported watchdog and kernel stall failures. Preserve shutdown exit status.
6. Under the same recorded host environment, show that the original image
   fails the unassisted bootstrap assertion and that the corrected image
   passes it. Configuration evaluation and repaired mock boot are insufficient.

Exact reproduction remains outstanding until the affected Chromebook or an
equivalent recorded ChromeOS environment is available. The audit does not
claim that a generic crosvm run can provide that evidence.
