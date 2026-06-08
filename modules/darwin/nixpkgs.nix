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
    # Keep the nix-darwin options manual free of raw /nix/store declaration
    # paths (Determinate Nix flags them); see the overlay for details.
    (import ../../overlays/darwin/options-doc-links.nix { inherit inputs; })
  ];
}
