# The ChromeOS integration and login account shared by our Baguette images.
# Keep this usable without the full dotfiles configuration.
{ config, inputs, ... }:
{
  imports = [
    inputs.nixos-crostini.nixosModules.baguette
    ../../modules/users.nix
    ../../modules/nixos/users.nix
  ];

  users.users.${config.mainUser} = {
    uid = 1000;
    # garcon must register the guest before ChromeOS can open a shell.
    # Start it and sommelier at boot, independent of login or /home storage.
    linger = true;
  };
}
