# The darwin `nixpkgs.overlays` are only ever assembled by a nix-darwin system,
# which this flake has no input for. The modules that define them are plain
# functions, though, so the fixpoint they end up in can be tied here: unstable
# built from the very overlay list it feeds. That is what makes an overlay
# reading `pkgsUnstable.<attr>` for an attr it also defines infinitely
# recursive, and it only surfaces once something forces that attr — which no
# base_hosts config does, since they leave `services.linux-builder` off and
# nix-rosetta-builder's launchd daemon is `lima`'s only consumer.
#
# So force every attribute the darwin overlays introduce. Pure evaluation, so it
# runs on the cheap Linux runners; only the derivation paths are written out.
{
  lib,
  writeText,
  # This flake's inputs, for the package sets the modules are given.
  inputs,
}:

let
  # Not a `callPackage` argument: that would fill it from the host package set.
  system = "aarch64-darwin";

  # `nixpkgs.overlays` as the module system would merge it: the shared module's
  # definition, then the darwin one's. Read off the modules rather than
  # relisted, so an overlay added to either is covered without touching this.
  shared = import ../modules/nixpkgs.nix {
    inherit lib inputs config;
    pkgs = pkgsDarwin;
  };
  darwin = import ../modules/darwin/nixpkgs.nix {
    inherit inputs config pkgsUnstable;
    pkgs = pkgsDarwin;
  };
  overlays = shared.config.nixpkgs.overlays ++ darwin.nixpkgs.overlays;

  # Stands in for the evaluated system: the modules only read their own options.
  config.nixpkgs = shared.config.nixpkgs // {
    allowUnfreeByName = [ ];
  };

  args = {
    inherit system;
    inherit overlays;
    inherit (config.nixpkgs) config;
  };
  pkgsDarwin = import inputs.nixpkgs-darwin args;
  # The recursion lives here: `modules/nixpkgs.nix` hands unstable the same
  # overlay list, so `pkgsUnstable.<attr>` resolves back through the overlay
  # that asked for it.
  pkgsUnstable = import inputs.nixpkgs-unstable args;

  # The overlay's own attribute names, resolved through the final package set —
  # the same trick `slim-closures` uses. Values are never forced here.
  introduced = lib.concatMap (o: builtins.attrNames (o pkgsDarwin pkgsDarwin)) darwin.nixpkgs.overlays;

  force =
    pkgs: name:
    let
      v = pkgs.${name};
    in
    if lib.isDerivation v then builtins.unsafeDiscardStringContext v.drvPath else builtins.typeOf v;
in

writeText "darwin-overlays" (
  builtins.toJSON (
    lib.genAttrs introduced (n: {
      stable = force pkgsDarwin n;
      unstable = force pkgsUnstable n;
    })
  )
)
