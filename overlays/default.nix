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

  (import ./argc.nix { inherit self; })
  (import ./mlx.nix { nixpkgs = self.inputs.nixpkgs-darwin; })
  (import ./packages.nix { inherit self; })
  # After packages.nix: it slims some of the packages defined there
  # (remarks), so it needs them in `prev`.
  (import ./slim.nix)
]
