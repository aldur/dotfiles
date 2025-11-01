{ config, ... }: {
  # Restrict `nix` user
  nix.settings = { allowed-users = [ config.users.users.aldur.name ]; };

  # Enable TouchID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
  security.pam.services.sudo_local.watchIdAuth = false;

  # Enable firewall
  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = true;
  };

}
