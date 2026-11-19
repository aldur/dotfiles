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
  # Root logs in with `ssh root@.host`.
  users.users.${config.mainUser}.initialHashedPassword = lib.mkForce null;
  users.allowNoPasswordLogin = true;
  # TODO: Temporary, for debugging. Remove.
  security.sudo-rs.wheelNeedsPassword = false;
  users.users.root.openssh.authorizedKeys.keys = config.identity.authorizedKeys;

  # No documentation. The index of man-db alone takes 40 s of CPU on the
  # first boot and 4 s on each boot after it.
  documentation = {
    enable = false;
    man.enable = false;
  };

  home-manager.users.${config.mainUser} = {
    programs.man.enable = false;
    manual.manpages.enable = false;
    home.packages = [
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.lazyvim-light
    ];
  };
}
