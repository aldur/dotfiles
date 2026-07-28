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
# bump them independently in CI (see
# .github/workflows/update-pinned-packages.yml). They stay reachable as
# `lazyvim.plugins.<name>` through the wrapper's passthru, mirroring how pi
# exposes its plugins, so they need no flake outputs of their own.
#
# The same spirit as utils/override-until-upgrade.nix, which guards the pin in
# ./tree-sitter-clarity.nix: nothing otherwise notices when a pin stops being
# necessary, and CI would keep bumping one we could have dropped (as
# venv-selector.nvim was, once nixpkgs caught up to the very rev it was pinned
# at). Fail loudly instead.
let
  upstreamed = lib.filter (name: vimPlugins ? ${name} || pkgsUnstable.vimPlugins ? ${name}) [
    "clarity-nvim"
    "link-vim"
    "tinymd-nvim"
  ];
in
lib.throwIf (upstreamed != [ ])
  ''
    nixpkgs now packages ${lib.concatStringsSep ", " upstreamed}, which packages/lazyvim/plugins pins by hand.
    Drop the pin (its file and the entry below), take it from vimPlugins in packages/lazyvim/plugins.nix, and remove its two legs from .github/workflows/update-pinned-packages.yml.''
  {
    clarity-nvim = callPackage ./clarity-nvim.nix { };
    link-vim = callPackage ./link-vim.nix { };
    tinymd-nvim = callPackage ./tinymd-nvim.nix { };
    tree-sitter-clarity = callPackage ./tree-sitter-clarity.nix { };
  }
