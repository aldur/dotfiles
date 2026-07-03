{ config, ... }:
{
  # Restrict `nix` user
  nix.settings = {
    allowed-users = [ config.mainUser ];
  };

  security.pam.services.sudo_local = {
    # Enable TouchID for sudo
    touchIdAuth = true;
    reattach = true;
    watchIdAuth = false;
  };

  # Enable firewall
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true;
    allowSigned = true;
    allowSignedApp = true;
  };

}
