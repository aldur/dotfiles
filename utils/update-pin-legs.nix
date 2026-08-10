# Turns discovered pins into a CI bump matrix, consumed by
# .github/workflows/update-pinned-packages.yml.
#
{ lib }:

{
  # Discovered pins per platform, from utils/discover-pins.nix. A package is
  # bumped on the platform that exposes it.
  linux,
  darwin,
  runners,
}:

let
  byPath = platform: lib.listToAttrs (map (e: lib.nameValuePair e.path e) platform);
  linuxByPath = byPath linux;
  darwinByPath = byPath darwin;

  preferDarwin =
    path:
    (darwinByPath.${path} or null) != null
    && darwinByPath.${path}.source == "packages"
    && (linuxByPath.${path} or { source = "overlay"; }).source != "packages";

  chosen =
    lib.mapAttrsToList (
      path: e:
      if preferDarwin path then
        darwinByPath.${path} // { runner = runners.darwin; }
      else
        e // { runner = runners.linux; }
    ) linuxByPath
    ++ map (e: e // { runner = runners.darwin; }) (lib.filter (e: !(linuxByPath ? ${e.path})) darwin);

  leg = e: {
    inherit (e) runner;
    # `lazyvim.plugins.foo` becomes the leg `foo`; the branch, PR and artifact
    # are named after it.
    package = e.name;
    attr = e.path;
    # nix-update's `--test` dies outright on a package with no
    # `passthru.tests`, so it is only requested when tests exist; a package
    # gaining tests still picks it up without touching the workflow.
    nix-update-args = lib.concatStringsSep " " (
      lib.optional ((e.drv.passthru.tests or { }) != { }) "--test"
      ++ lib.optional ((e.pin.args or "") != "") e.pin.args
    );
    # Building a passthru derivation on its own often proves little — a Neovim
    # plugin is just Lua copied into the store — so the default builds whatever
    # top-level package it reaches the tree through.
    verify = e.pin.verify or "nix build .#${e.root}";
  };

  bumped = lib.filter (e: !(e.pin ? exempt)) chosen;

  # nix-update finds a package in `packages.<system>`, then at the flake
  # root. It does not read the overlay. A leg for a package that only the
  # overlay has fails on the runner. The error is `expected a set but found
  # null`.
  #
  # This test is here, and not in checks/pinned-packages.nix, because only
  # this file sees the two platforms. A darwin-only package is in the overlay
  # on Linux, but the flake exports it on the runner that bumps it.
  unresolvable = lib.filter (e: e.source == "overlay") bumped;
in

lib.throwIf (unresolvable != [ ]) (
  "update pins:\n  "
  + lib.concatStringsSep "\n  " (
    map (
      e: "`${e.path}` is bumped on ${e.runner}, where only the overlay defines `${e.root}`"
    ) unresolvable
  )
  + "\n\n  nix-update resolves it through the flake's outputs, so export it from"
  + " `packages` (or reach it through the `passthru` of one that is exported)."
) (map leg bumped)
