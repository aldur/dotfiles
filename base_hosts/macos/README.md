# `nix-darwin` configuration

This Flake allows creating a [`nix-darwin`][0] configuration with the modules
of this repository.

## Building

Use:

```bash
sudo darwin-rebuild --flake .#macOS switch
```

## Bootstrapping

On Apple Silicon, install [`nix`][1] and run this as user `aldur` (UID 501):

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  run nix-darwin/master#darwin-rebuild -- switch \
  --flake 'github:aldur/dotfiles?dir=base_hosts/macos#macOS'
```

## Configuration

See `macos.nix` for how to customize the install.

[0]: https://github.com/nix-darwin/nix-darwin
[1]: https://nixos.org/download/
