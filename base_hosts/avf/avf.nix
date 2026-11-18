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
    ./smartcard.nix
    "${inputs.self}/modules/current_system_flake.nix"
    "${inputs.self}/modules/nixos/ssh-local-root.nix"
  ];

  networking.hostName = "avf-nixos";
  system.stateVersion = "26.05";

  # The user has no password: ttyd logs in with `login -f`. As in the qemu
  # guests, the VM boundary and the phone lock screen protect the account.
  # Thus sudo does not work. Root logs in with `ssh root@.host`.
  users.users.${config.mainUser}.initialHashedPassword = lib.mkForce null;
  users.allowNoPasswordLogin = true;
  users.users.root.openssh.authorizedKeys.keys = config.identity.authorizedKeys;

  # The `doc` outputs of the system packages, the info manuals and the NixOS
  # manual. The man pages stay.
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.nixos.enable = false;

  home-manager.users.${config.mainUser}.home.packages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.lazyvim-light
  ];
}
