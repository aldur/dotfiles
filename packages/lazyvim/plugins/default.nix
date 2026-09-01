{
  callPackage,
  lib,
  vimPlugins,
  # A plugin lands in unstable first, and ./plugins.nix already takes some from
  # there, so both channels count as "nixpkgs has it".
  pkgsUnstable,
}:

# Plugins pinned to an upstream rev instead of taken from nixpkgs' vimPlugins,
# because nixpkgs packages nothing equivalent. One file each, so nix-update can
# bump them independently: each carries its own `passthru.updatePin`, which is
# what puts it in CI's matrix. They stay reachable as `lazyvim.plugins.<name>`
# through the wrapper's passthru, so they need no flake outputs of their own.
#
# The same spirit as utils/override-until-upgrade.nix, which guards the pin in
# ./tree-sitter-clarity.nix: nothing otherwise notices when a pin stops being
# necessary, and CI would keep bumping one we could have dropped (as
# venv-selector.nvim was, once nixpkgs caught up to the very rev it was pinned
# at). Fail loudly instead.
let
  plugins = {
    clarity-nvim = callPackage ./clarity-nvim.nix { };
    tinymd-nvim = callPackage ./tinymd-nvim.nix { };
    tree-sitter-clarity = callPackage ./tree-sitter-clarity.nix { };
  };

  # Derived from the set above rather than listed again, so a plugin added
  # here cannot slip through unguarded. `attrNames` does not force the values,
  # so naming the set from within its own guard is fine. tree-sitter-clarity is
  # a grammar rather than a vimPlugins entry and carries its own guard.
  upstreamed = lib.filter (name: vimPlugins ? ${name} || pkgsUnstable.vimPlugins ? ${name}) (
    lib.attrNames (removeAttrs plugins [ "tree-sitter-clarity" ])
  );
in
lib.throwIf (upstreamed != [ ]) ''
  nixpkgs now packages ${lib.concatStringsSep ", " upstreamed}, which packages/lazyvim/plugins pins by hand.
  Drop the pin (its file and the entry above).'' plugins
