# update-pins

Bump machinery for packages that pin a source (`fetchFromGitHub` and
friends). It has three parts:

1. `lib.updatePins.discover` walks a package set. It finds every derivation
   that fetches a pinned source, and reads its optional
   `passthru.updatePin`.
2. `lib.updatePins.mkLegs` turns the discovered pins into a list of legs.
   Each leg carries a `bump` command (nix-update), a `verify` command, a
   `runner`, an `os`, and the `cooldown` data.
3. This package, `update-pins`, runs the legs. It reads
   `nix eval --json .#updatePins` from the current directory, so it works
   on any flake that exports `updatePins`.

## Tune a package with `passthru.updatePin`

- `args`: extra nix-update flags, as one string. Example:
  `"--version=branch"`.
- `verify`: the shell command that proves the bump. The default builds the
  top-level package the pin belongs to.
- `exempt`: set it (any value) to skip the package.
- `cooldown`: set it to `false` to bump the package without a cooldown.

A package without `passthru.updatePin` still gets a leg, with the defaults.

## Cooldown

With a cooldown of three days, a leg takes only an upstream state that is
at least three days old. A defective or malicious release then has time to
be found before it gets here. `cooldown.py` selects the state before
nix-update runs, so a state that is too new is not fetched or built.

The cooldown is off by default. Set `cooldown.days` in the call of `mkLegs`
to enable it. `cooldown.exemptOwners` is a list of GitHub owners that get
no cooldown.

| Source | State that the leg takes | Age comes from |
|---|---|---|
| GitHub branch (`--version=branch`) | The head of the branch three days ago | The push time, from the repository activity API |
| GitHub release | The newest release, not a pre-release | The publication time of the release |
| PyPI | The newest final version | The upload time of its files |

These times come from the server. The commit date does not: the author of
a commit sets it.

- A leg never goes back to a state that is older than the pin.
- If the data is not available, the leg fails and does not bump. This
  includes a source that is not GitHub or PyPI, and a GitHub repository
  that has tags but no releases.
- Set `GITHUB_TOKEN` to raise the rate limit of the GitHub API.
- `update-pins --no-cooldown <name>` takes the newest state.

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
