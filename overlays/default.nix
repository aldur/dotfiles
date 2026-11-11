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

  (import ./direnv { inherit self; })

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

  # The cargo setup hook of nixpkgs tells the `-sys` crates to use the system
  # libraries (for example AWS_LC_SYS_USE_SYSTEM=1). The recipe for codex
  # 0.167.0 does not list four of them, thus the build fails ("requires a
  # system-installed AWS-LC"). The binary cache has no codex 0.167.0 for
  # Linux or Darwin, so each platform builds it from source.
  #
  # nixpkgs master has the correction since 0.167.1, in
  # pkgs/by-name/co/codex/package.nix. On 2026-11-11 the nixos-unstable
  # channel, which flake.lock follows, did not have it. This override
  # applies to 0.167.0 only. Remove it after the first `nix flake update`
  # that brings a different codex version.
  (_final: prev: {
    codex =
      if prev.codex.version == "0.167.0" then
        prev.codex.overrideAttrs (old: {
          buildInputs = old.buildInputs ++ [
            prev.aws-lc
            prev.oniguruma
            prev.sqlite
            prev.zstd
          ];
        })
      else
        prev.codex;
  })

  (import ./argc.nix { inherit self; })
  (import ./mlx.nix { nixpkgs = self.inputs.nixpkgs-darwin; })
  (import ./packages.nix { inherit self; })
  # After packages.nix: it slims some of the packages defined there
  # (remarks), so it needs them in `prev`.
  (import ./slim.nix { inherit self; })

  # `pkgsUnstable` also gets this list. nixpkgs-unstable has the fixes, so
  # the expiry guards of these overrides throw there. Use the stock packages
  # on that set only. Delete a name here when you delete its override.
  (
    _final: prev:
    prev.lib.optionalAttrs (toString prev.path == toString self.inputs.nixpkgs-unstable) {
      inherit (self.inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system})
        nix-direnv
        apparmor-parser
        ;
    }
  )
]
