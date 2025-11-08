{ inputs, pkgs, ... }:
let
  lazyvim = import ../packages/lazyvim/lazyvim.nix { inherit inputs pkgs; };
in
{
  imports = [
    lazyvim.defaultModule
  ];

  home-manager.users.aldur =
    { config, ... }: # home-manager's config, not the OS one
    {
      imports = [ lazyvim.defaultHomeModule ];
    };
}
