{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ (import ../../overlays/darwin/jailed-lazyvim.nix { inherit inputs pkgs; }) ];
}
