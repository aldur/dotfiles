{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  lazyvim = import ../packages/lazyvim/lazyvim.nix { inherit inputs pkgs pkgsUnstable; };
in
{
  imports = [
    lazyvim.defaultModule
  ];
}
