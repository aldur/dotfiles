{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./terminal-guest.nix
    "${inputs.self}/modules/current_system_flake.nix"
  ];

  networking.hostName = "avf-nixos";
  system.stateVersion = "26.05";

  # The user has no password: ttyd logs in with `login -f`. As in the qemu
  # guests, the VM boundary and the phone lock screen protect the account.
  users.users.${config.mainUser}.initialHashedPassword = lib.mkForce null;
  users.allowNoPasswordLogin = true;
  security.sudo-rs.wheelNeedsPassword = false;

  home-manager.users.${config.mainUser}.home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.lazyvim-light
  ];
}
