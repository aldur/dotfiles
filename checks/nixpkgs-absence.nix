{
  lib,
  runCommand,
  stdenv,
  # This repo's packages, as candidates to look for the marker on.
  candidates,
  # nixpkgs without this repo's overlay, which would otherwise hide the very
  # attribute being looked for.
  upstream,
}:

# Asserts that nothing carrying `passthru.absentFromNixpkgs` has since landed
# in nixpkgs.
#
# A package here only to fill a gap in nixpkgs quietly stops being that once
# nixpkgs fills the gap itself: the overlay keeps shadowing it, and the local
# copy — with whatever it does differently — is what everything gets. This
# fails the flake check instead, so the local copy gets dropped (or kept
# deliberately, by removing the marker).
#
# Pure evaluation, so the cheap `nix flake check --no-build` job catches it.

let
  landed = lib.concatLists (
    lib.mapAttrsToList (
      name: package:
      let
        # Overlay attributes that cannot be evaluated on this platform are not
        # this check's business.
        attr = (builtins.tryEval (package.absentFromNixpkgs or null)).value or null;
      in
      lib.optional (
        attr != null && upstream ? ${attr}
      ) "`${attr}`, which this repo packages as `${name}` only because it did not"
    ) candidates
  );
in

# Concatenated rather than written as an indented string: interpolating newlines
# into one of those does not re-indent, and the report comes out ragged.
lib.throwIf (landed != [ ]) (
  "nixpkgs now ships (${stdenv.hostPlatform.system}):\n  "
  + lib.concatStringsSep "\n  " landed
  + "\n\n  Delete the local package and use nixpkgs', or drop"
  + " `passthru.absentFromNixpkgs` to keep packaging it here on purpose."
) (runCommand "nixpkgs-absence-check" { } "touch $out")
