{
  inputs,
  lib,
  pkgs,
  pkgsUnstable,
  config,
  ...
}:
let
  lazyvim = import ../packages/lazyvim/lazyvim.nix { inherit inputs pkgs pkgsUnstable; };
in
{
  imports = [
    lazyvim.defaultModule
  ];

  home-manager.users = lib.genAttrs config.interactiveUsers (_: {
    imports = [ lazyvim.defaultHomeModule ];
  });
}
