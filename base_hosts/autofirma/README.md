# `autofirma` VM guest

A NixOS guest for [AutoFirma][0], the signing tool of the Spanish
government, with Firefox. It runs as a QEMU VM with an XFCE desktop, or as
a [ChromeOS Baguette][2] image.

AutoFirma talks to the browser over a TLS WebSocket on `127.0.0.1`. To make
the browser trust that socket, its installer adds a self-made root CA to the
system trust store. In this VM, the CA stays in `/etc/Autofirma` and in the
guest Firefox. The host trust store does not change.

The packages come from [autofirma-nix][1]. `guest.nix` holds what runs.
`desktop.nix` adds the XFCE session of the QEMU VM. `autofirma.nix` holds
the QEMU VM settings. `baguette.nix` holds the Baguette image.

## Quick start

```bash
# On the Mac, or on any host with the qemu-vm package
nix run "github:aldur/dotfiles?dir=base_hosts/autofirma" -- \
  --gui -p 22:2222 --file cert.p12=/path/to/cert.p12
```

The guest logs `aldur` in. A dialog asks for the certificate password.
Firefox then opens on a start page with links to the usual sedes. The
serial console stays on the terminal. `Ctrl-b c` switches to the QEMU
monitor.

## Sessions

The VM is ephemeral by default. QEMU discards all disk writes at exit, so
the Firefox profile, the cookies, the certificate, and the AutoFirma root
CA do not survive a session. `--file` brings the certificate in each time.
QEMU exposes the file through firmware config, not through the network.
`--persistent` keeps the disk under `~/.local/share/autofirma-vm`.

To skip the password dialog, pass the password as a file too:
`--file cert.password=/path/to/password`.

## Clipboard

The clipboard is shared with the host by default. QEMU speaks the vdagent
protocol to the guest, and the guest runs `spice-vdagent`. `--no-clipboard`
turns it off. Other guests get this only with `--clipboard`, and only if
they run `services.spice-vdagentd`.

The display must take part. The Cocoa display on macOS does. The GTK
display on Linux does not: nixpkgs builds QEMU without its experimental
`gtk-clipboard` option. A VNC client does.

## Certificate by hand

Without `--file`, copy the certificate over SSH. The guest sshd has no
SFTP, so `scp` does not work:

```bash
cat cert.p12 | ssh -p 2222 aldur@localhost "cat - > cert.p12"
```

Then, in a terminal in the guest, run `import-certificate cert.p12` and
restart Firefox.

## Baguette

The workflow `baguette-image.yml` builds the arm64 image on demand
(`workflow_dispatch`, image `autofirma`) and keeps it as the artifact
`autofirma-baguette-arm64` for a few days. The push pipeline only builds
the system closure as a test. Download the artifact, then create the VM in
`crosh`:

```bash
gh run download --repo aldur/dotfiles --name autofirma-baguette-arm64

vmc create --vm-type BAGUETTE --size 10G \
  --source /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img.zst \
  autofirma
vmc start --vm-type BAGUETTE autofirma
```

To build the image yourself:

```bash
nix build .#baguette-zimage
```

ChromeOS shows the Firefox window through sommelier. There is no desktop in
the guest. Start "Firefox (AutoFirma)" from the launcher, or run
`autofirma-vm-firefox` in `vsh autofirma penguin`. The wrapper imports
`cert.p12` from the Downloads folder of ChromeOS once that folder is shared
with Linux. `/home` is a tmpfs, so the profile and the certificate do not
survive `vmc stop`.

The image does not import the dotfiles base module. It has no shell tools,
no home-manager, no sshd, no `nixos-rebuild`, no documentation, no mesa
(Firefox renders in software; the sommelier of ChromeOS brings its own
libraries), and no kernel: Baguette boots the ChromeOS kernel. Firefox
comes without ffmpeg, pipewire, and GStreamer. See the "Size" sections of
`baguette.nix` and `guest.nix`. The closure is 1.5 GiB, and the compressed
image is 0.5 GiB. Firefox itself is 0.4 GiB of the closure, and the trimmed
JRE 0.1 GiB.

## Test

`nix flake check` runs `tests/sign-via-websocket.nix`. The test boots the
QEMU guest with a self-signed certificate passed the way `--file` does. The
session wrapper imports it into Firefox. Then the test opens a local HTTPS
page that uses AutoScript and clicks its button. It asserts that AutoFirma
returns a signature over the WebSocket. The test needs KVM.

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
```

If the test fails, build it with `diagnose = true` (an argument of the
file). It then prints the processes, the Firefox console, and the screen
text. It does not assert.

`nix flake check` also runs a Baguette boot test. It boots the image in
crosvm, as ChromeOS does, and probes it: the stage-2 init without initrd,
the btrfs root and its resize, userborn, the tmpfs home, sommelier, the
AutoFirma CA, the launcher entries, a Firefox screenshot of the start page,
the certificate import, and the AutoFirma launch on the trimmed JRE.

```bash
nix build .#checks.x86_64-linux.baguette-boot -L
```

The generic half lives in `utils/baguette-test.nix` of the dotfiles, as
`lib.mkBaguetteTest`. Any flake that builds a Baguette image can call it
with its `nixosSystem`, and add its own probe lines and checks. This flake
passes the AutoFirma ones.

The image has no kernel, so the test boots it with the kernel and initrd of
the same configuration. ChromeOS also mounts a `cros-vm-tools` disk with
maitred, vshd, garcon, and sommelier. Those binaries are not public, and
only sommelier has a source build (in nixpkgs). The test mounts a disk with
that label carrying sommelier and stand-ins for the other daemons. So it
covers the guest side of the integration. The host side does not exist
outside ChromeOS: maitred and garcon talk to concierge and cicerone, which
have no standalone build. Windows reach the host through a virtio-gpu
cross-domain context; the crosvm of nixpkgs does not serve that context, so
the test asserts that sommelier runs, not that a window appears.

## Notes

- There is no shared folder. The nixpkgs QEMU on macOS has no 9p. Use
  `--file` for files into the guest, or SSH with `cat` (see above).
- The QEMU guest closure is 4.2 GiB. See the "Size" sections of `guest.nix`
  and `desktop.nix`. Firefox, XFCE, and the LLVM of mesa stay large.
- The Maven dependency hashes in `guest.nix` differ from the upstream ones.
  The comment there says how to refresh them.

[0]: https://firmaelectronica.gob.es/Home/Descargas.html
[1]: https://github.com/nix-community/autofirma-nix
[2]: https://github.com/aldur/nixos-crostini
