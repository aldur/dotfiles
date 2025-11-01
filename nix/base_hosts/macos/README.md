# `nix-darwin` configuration

This Flake allows creating a [`nix-darwin`][0] configuration with the modules
of this repository. Using [Determinate Nix][1] will also provide a native Linux
builder.

## Building

Use:

```bash
sudo darwin-rebuild --flake .#macOS switch
```

## Configuration

See `macos.nix` for how to customize the install.

[0]: https://github.com/nix-darwin/nix-darwin
[1]: https://determinate.systems
