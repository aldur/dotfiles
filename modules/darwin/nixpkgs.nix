{
  inputs,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  nixpkgs.overlays = [
    (import ../../overlays/darwin/jailed-lazyvim.nix { inherit inputs pkgs pkgsUnstable; })
    (import ../../overlays/darwin/fish.nix)
    # lima wraps limactl with the full qemu (~2.3GiB closure) for its qemu
    # driver; nix-rosetta-builder only ever uses the Virtualization.framework
    # driver. qemu-utils (~140MiB) keeps qemu-img for disk-image handling.
    (_final: _prev: { lima = unstable.lima.override { qemu = unstable.qemu-utils; }; })
  ];
}
