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
    nix-update-args = e.pin.args or "";
    # Building a passthru derivation on its own often proves little — a Neovim
    # plugin is just Lua copied into the store — so the default builds whatever
    # top-level package it reaches the tree through.
    verify = e.pin.verify or "nix build .#${e.root} -L";
  };
in

map leg (lib.filter (e: !(e.pin ? exempt)) chosen)
