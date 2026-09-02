# `autofirma` VM guest

A NixOS guest for [AutoFirma][0], the Spanish government signing tool, with
Firefox and an XFCE desktop.

AutoFirma talks to the browser over a TLS WebSocket on `127.0.0.1`. To make
the browser trust that socket, its installer adds a self-made root CA to the
system trust store. In this VM the CA lands in `/etc/Autofirma` and in the
guest's Firefox. The host trust store stays untouched.

Packaging comes from [autofirma-nix][1]. See `guest.nix` for what runs and
`autofirma.nix` for the VM plumbing.

## Quick start

```bash
# On the Mac (or any host with the qemu-vm package)
nix run "github:aldur/dotfiles?dir=base_hosts/autofirma" -- --gui -p 22:2222
```

The guest logs `aldur` in and opens Firefox on a start page with links to
the usual sedes. The serial console stays on the terminal; `Ctrl-b c`
switches to the QEMU monitor.

## First run: your certificate

AutoFirma reads certificates from the Firefox store. Import yours once:

1. On the host: `scp -P 2222 cert.p12 aldur@localhost:`
2. In a guest terminal: `import-certificate cert.p12`
3. Restart Firefox.

The disk under `~/.local/share/autofirma-vm` keeps the profile between runs.
`--clean` starts over.

## Test

`nix flake check` runs `tests/sign-via-websocket.nix`. It boots the guest,
imports a self-signed test certificate into Firefox, opens a local HTTPS
page that uses AutoScript, clicks its button, and asserts that AutoFirma
returns a signature over the WebSocket. It needs KVM.

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
```

When it fails, build the test with `diagnose = true` (see the file's
arguments): it prints processes, Firefox's console and the screen text
instead of asserting.

## Notes

- No shared folder: the nixpkgs QEMU on macOS has no 9p. Use `scp`.
- Two Maven dependency hashes in autofirma-nix are stale; `guest.nix` pins
  the observed ones and says when to drop the override.

[0]: https://firmaelectronica.gob.es/Home/Descargas.html
[1]: https://github.com/nix-community/autofirma-nix
