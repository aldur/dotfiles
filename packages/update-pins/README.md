# update-pins

Bump machinery for packages that pin a source (`fetchFromGitHub` and
friends). It has three parts:

1. `lib.updatePins.discover` walks a package set. It finds every derivation
   that fetches a pinned source, and reads its optional
   `passthru.updatePin`.
2. `lib.updatePins.mkLegs` turns the discovered pins into a list of legs.
   Each leg carries a `bump` command (nix-update), a `verify` command, a
   `runner`, and an `os`.
3. This package, `update-pins`, runs the legs. It reads
   `nix eval --json .#updatePins` from the current directory, so it works
   on any flake that exports `updatePins`.

## Tune a package with `passthru.updatePin`

- `args`: extra nix-update flags, as one string. Example:
  `"--version=branch"`.
- `verify`: the shell command that proves the bump. The default builds the
  top-level package the pin belongs to.
- `exempt`: set it (any value) to skip the package.

A package without `passthru.updatePin` still gets a leg, with the defaults.

## Use from another flake

```nix
{
  inputs.aldur-dotfiles.url = "github:aldur/dotfiles";

  outputs = { self, nixpkgs, aldur-dotfiles, ... }: {
    legacyPackages.x86_64-linux.discoveredPins =
      aldur-dotfiles.lib.updatePins.discover { inherit (nixpkgs) lib; } {
        inherit self;
        packages = self.packages.x86_64-linux;
        inherit (nixpkgs.legacyPackages.x86_64-linux.stdenv) hostPlatform;
      };

    # `darwin` and `runners` have defaults; override them when needed.
    updatePins = aldur-dotfiles.lib.updatePins.mkLegs { inherit (nixpkgs) lib; } {
      linux = self.legacyPackages.x86_64-linux.discoveredPins;
    };
  };
}
```

Then, from the consumer repository:

```sh
nix run github:aldur/dotfiles#update-pins            # list the legs
nix run github:aldur/dotfiles#update-pins -- <name>  # bump one, then verify
```

For CI, copy `.github/workflows/update-pinned-packages.yml`. The legs
carry the runner and the commands, so the workflow stays thin.
