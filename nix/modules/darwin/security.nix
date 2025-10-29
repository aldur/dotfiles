{
  user,
  ...
}:
{
  # Restrict `nix` user
  nix.settings = {
    allowed-users = [ user ];
  };

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
