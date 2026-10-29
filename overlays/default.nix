{ self }:
[
  (
    final: prev:
    let
      overridesDir = ./overrides;

      # Get list of overlay functions
      overlays = builtins.map (name: import (overridesDir + "/${name}")) (
        builtins.filter (name: builtins.match ".*\\.nix" name != null) (
          builtins.attrNames (builtins.readDir overridesDir)
        )
      );
    in
    prev.lib.composeManyExtensions overlays final prev
  )

  (final: prev: {
    # SQLite 3.53 changed SQL BLOB literals from X'...' to x'...' and broke
    # pnpm archive hashes in stable. Use the fixed fetcher from the existing
    # unstable input; callPackages supplies this package set's build tools.
    # Fix: https://github.com/NixOS/nixpkgs/commit/29ee10df315af79c26065b836197a2142a485ab5
    # Remove this overlay when both stable inputs, nixpkgs and nixpkgs-darwin,
    # normalize SQL BLOB literals to X'...' before archiving the pnpm store.
    fetchPnpmDeps =
      (prev.callPackages (self.inputs.nixpkgs-unstable + "/pkgs/build-support/node/fetch-pnpm-deps") { })
      .fetchPnpmDeps;
  })

  (import ./argc.nix { inherit self; })
  (import ./mlx.nix { nixpkgs = self.inputs.nixpkgs-darwin; })
  (import ./packages.nix { inherit self; })
  # After packages.nix: it slims some of the packages defined there
  # (remarks), so it needs them in `prev`.
  (import ./slim.nix)
]
