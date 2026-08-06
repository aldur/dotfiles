# Wrap `nixosOptionsDoc` so the options manual's "Declared by" links never bake a
# raw /nix/store path into options.json (which Determinate Nix flags as an
# untracked store reference).  nixpkgs-sourced declarations (lib/modules.nix,
# nixos/modules/misc/*) become real github.com/NixOS/nixpkgs blob URLs at the
# exact locked revision; anything else is reduced to a context-free relative path.
#
# NixOS, nix-darwin and home-manager each build such a manual, and each only
# rewrites declarations under its own source tree, leaving nixpkgs ones as store
# paths (e.g. home-manager's `meta.maintainers`, declared by nixpkgs'
# modules/generic/meta-maintainers.nix).  Applied once to the system pkgs in
# modules/nixpkgs.nix, which both platforms import; because
# `home-manager.useGlobalPkgs` makes home-manager evaluate against that same
# package set, its `man home-configuration.nix` (built via
# `pkgs.buildPackages.nixosOptionsDoc`) inherits the wrapped derivation too.
#
# It has to sit on the shared path, not the darwin one: modules/home/qemu-vm.nix
# evaluates a whole nixosSystem off the plain `nixpkgs` input, and that guest's
# home-manager manual is otherwise built by a package set no darwin-only overlay
# reaches.
{ inputs }:
_final: prev:
let
  lib = prev.lib;
  storePrefix = builtins.storeDir + "/";

  isNixpkgs = src: builtins.pathExists (src + "/pkgs/top-level/all-packages.nix");
  nixpkgsSrcs = lib.filter (
    i: builtins.isAttrs i && (i ? outPath) && (i ? rev) && isNixpkgs i.outPath
  ) (builtins.attrValues inputs);

  ghBlob = rev: subpath: {
    url = "https://github.com/NixOS/nixpkgs/blob/${rev}/${subpath}";
    name = "<nixpkgs/${subpath}>";
  };

  scrubDecl =
    d:
    if builtins.isString d || builtins.isPath d then
      let
        s = toString d;
      in
      if lib.hasPrefix storePrefix s then
        let
          hit = lib.findFirst (i: lib.hasPrefix (toString i.outPath + "/") s) null nixpkgsSrcs;
        in
        if hit != null then
          ghBlob hit.rev (lib.removePrefix (toString hit.outPath + "/") s)
        else
          let
            parts = lib.splitString "/" (lib.removePrefix storePrefix s);
            rest = lib.concatStringsSep "/" (builtins.tail parts);
            name = lib.concatStringsSep "-" (builtins.tail (lib.splitString "-" (builtins.head parts)));
          in
          if rest == "" then name else "${name}/${rest}"
      else
        d
    else
      d;
in
{
  nixosOptionsDoc =
    args:
    prev.nixosOptionsDoc (
      args
      // {
        transformOptions =
          opt:
          let
            o = (args.transformOptions or lib.id) opt;
          in
          o // { declarations = map scrubDecl o.declarations; };
      }
    );
}
