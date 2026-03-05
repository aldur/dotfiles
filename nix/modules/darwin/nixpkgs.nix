{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:
{
  nixpkgs.overlays = [
    (import ../../overlays/darwin/jailed-lazyvim.nix { inherit inputs pkgs pkgsUnstable; })
  ];
}
