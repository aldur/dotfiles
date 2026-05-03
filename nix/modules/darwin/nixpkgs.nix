{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:
{
  nixpkgs.overlays = [
    (import ../../overlays/darwin/jailed-lazyvim.nix { inherit inputs pkgs pkgsUnstable; })
    (import ../../overlays/darwin/fish.nix)
    (_final: _prev: { lima = pkgsUnstable.lima; })
  ];
}
