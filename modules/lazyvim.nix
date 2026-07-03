{
  inputs,
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

  home-manager.users.${config.mainUser}.imports = [ lazyvim.defaultHomeModule ];
}
