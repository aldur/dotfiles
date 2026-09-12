# The ChromeOS integration and login account shared by our Baguette images.
# Keep this usable without the full dotfiles configuration.
{ config, inputs, ... }:
{
  imports = [
    inputs.nixos-crostini.nixosModules.baguette
    ../../modules/users.nix
    ../../modules/nixos/users.nix
  ];

  users.users.${config.mainUser}.crostini.enable = true;
}
