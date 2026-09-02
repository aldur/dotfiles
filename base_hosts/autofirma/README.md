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
nix run "github:aldur/dotfiles?dir=base_hosts/autofirma" -- --gui -p 22:2222
```

The guest logs `aldur` in and opens Firefox on a start page. The page has
links to the usual sedes. The serial console stays on the terminal.
`Ctrl-b c` switches to the QEMU monitor.

## First run: your certificate

AutoFirma reads the certificates from the Firefox store. Import your
certificate one time:

1. On the host, copy the file over SSH. The guest sshd has no SFTP, so
   `scp` does not work:

   ```bash
   cat cert.p12 | ssh -p 2222 aldur@localhost "cat - > cert.p12"
   ```

2. In a terminal in the guest: `import-certificate cert.p12`
3. Restart Firefox.

The disk under `~/.local/share/autofirma-vm` keeps the profile between runs.
`--clean` removes it.

## Test

`nix flake check` runs `tests/sign-via-websocket.nix`. The test boots the
guest and imports a self-signed test certificate into Firefox. Then it opens
a local HTTPS page that uses AutoScript and clicks its button. It asserts
that AutoFirma returns a signature over the WebSocket. The test needs KVM.

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
```

If the test fails, build it with `diagnose = true` (an argument of the
file). It then prints the processes, the Firefox console, and the screen
text. It does not assert.

## Notes

- There is no shared folder. The nixpkgs QEMU on macOS has no 9p. Copy
  files over SSH with `cat` (see above).
- The guest closure is 4.8 GiB. See the "Size" section of `guest.nix`. The
  JDK, Firefox, and the LLVM of mesa stay large.
- The Maven dependency hashes in `guest.nix` differ from the upstream ones.
  The comment there says how to refresh them.

[0]: https://firmaelectronica.gob.es/Home/Descargas.html
[1]: https://github.com/nix-community/autofirma-nix
