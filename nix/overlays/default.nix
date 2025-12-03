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

  (import ./packages.nix)
]
