# The self-reference rewrite of Nix damages the code signature of the
# stripped fish binary (NixOS/nixpkgs#507531, NixOS/nix#15638). The
# unstripped build keeps a valid signature.
#
# The override gives fish a new derivation. Each package with fish as a
# build input then builds from source on the macOS runner, with its test
# suite. neovim runs its functional tests with fish. It gets the stock
# fish, so it keeps the cached derivation. checks/darwin-overlays.nix
# makes sure of that.
(
  final: prev:
  let
    inherit (final) lib;
  in
  {
    fish = prev.fish.overrideAttrs (_old: {
      dontStrip = true;
    });
    # Replace fish only if the package has a fish argument. The neovim of
    # nixpkgs-unstable does not have one.
    neovim-unwrapped = prev.neovim-unwrapped.override (
      args: lib.optionalAttrs (args ? fish) { fish = prev.fish; }
    );
  }
)
