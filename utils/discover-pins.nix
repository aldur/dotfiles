# Finds every package in this repo that fetches a pinned source, and reads the
# `passthru.updatePin` each is expected to carry.
{ lib }:

{
  # This system's flake package outputs, and the attributes this repo's overlay
  # adds to nixpkgs. The latter are often never promoted to flake outputs, and
  # so they'd be invisible.
  packages,
  overlayPackages ? { },
  # The flake, to tell derivations defined in this repo from nixpkgs'.
  self,
  # Used to drop overlay attributes that cannot be built here at all, so a
  # macOS-only tool is not reported as a Linux pin.
  hostPlatform,
}:

let
  try = fallback: v: (builtins.tryEval v).value or fallback;
  isDrv = v: try false (lib.isDerivation v);
  # nixpkgs' own tree is also a store path, so match this flake's exactly.
  definedHere = d: try false (lib.hasPrefix "${self}" (d.meta.position or ""));
  # A fetched source is a derivation in its own right (fetchFromGitHub and
  # friends); packages built from a local path or a script have none.
  fetchesSource = d: d ? src && lib.isDerivation d.src;

  # Also look one level into passthru, where this repo keeps derivations that
  # have pins of their own: a `plugins` collection (pi, lazyvim) and, for
  # wrappers with no source, the real package (remarks).
  walk =
    path: drv:
    [ { inherit path drv; } ]
    ++ lib.concatLists (
      lib.mapAttrsToList (
        n: v:
        if isDrv v then
          lib.optional (definedHere v) {
            path = "${path}.${n}";
            drv = v;
          }
        else if n == "plugins" && builtins.isAttrs v then
          lib.mapAttrsToList (pn: pv: {
            path = "${path}.plugins.${pn}";
            drv = pv;
          }) (lib.filterAttrs (_: isDrv) v)
        else
          [ ]
      ) (drv.passthru or { })
    );

  # Overlay attributes are only worth walking when this repo defines them; the
  # overlay also re-exports packages straight from nixpkgs-unstable.
  overlayOnly = lib.filterAttrs (
    n: v: !(packages ? ${n}) && definedHere v && try false (lib.meta.availableOn hostPlatform v)
  ) overlayPackages;

  found =
    source: set:
    lib.concatLists (
      lib.mapAttrsToList (n: v: if isDrv v then map (e: e // { inherit source; }) (walk n v) else [ ]) set
    );
in

map (e: {
  inherit (e) path drv source;
  # `foo.plugins.bar` names the leg `bar`; `foo.bar` (a wrapper's real
  # package) names it `foo`, which is what gets built to verify it.
  name = lib.last (lib.splitString "." e.path);
  root = lib.head (lib.splitString "." e.path);
  pin = e.drv.updatePin or null;
}) (lib.filter (e: fetchesSource e.drv) (found "packages" packages ++ found "overlay" overlayOnly))
