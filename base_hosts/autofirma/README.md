# `autofirma` VM guest

A NixOS guest for [AutoFirma][0], the signing tool of the Spanish
government, with Firefox and an XFCE desktop.

AutoFirma talks to the browser over a TLS WebSocket on `127.0.0.1`. To make
the browser trust that socket, its installer adds a self-made root CA to the
system trust store. In this VM, the CA stays in `/etc/Autofirma` and in the
guest Firefox. The host trust store does not change.

The packages come from [autofirma-nix][1]. `guest.nix` holds what runs.
`autofirma.nix` holds the VM settings.

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

## Test

`nix flake check` runs `tests/sign-via-websocket.nix`. The test boots the
guest with a self-signed certificate passed the way `--file` does. The
session wrapper imports it into Firefox. Then the test opens a local HTTPS
page that uses AutoScript and clicks its button. It asserts that AutoFirma
returns a signature over the WebSocket. The test needs KVM.

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
```

If the test fails, build it with `diagnose = true` (an argument of the
file). It then prints the processes, the Firefox console, and the screen
text. It does not assert.

## Notes

- There is no shared folder. The nixpkgs QEMU on macOS has no 9p. Use
  `--file` for files into the guest, or SSH with `cat` (see above).
- The guest closure is 4.8 GiB. See the "Size" section of `guest.nix`. The
  JDK, Firefox, and the LLVM of mesa stay large.
- The Maven dependency hashes in `guest.nix` differ from the upstream ones.
  The comment there says how to refresh them.

[0]: https://firmaelectronica.gob.es/Home/Descargas.html
[1]: https://github.com/nix-community/autofirma-nix
