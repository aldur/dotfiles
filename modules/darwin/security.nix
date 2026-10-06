{
  config,
  lib,
  ...
}:
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

  users.users.${config.mainUser}.openssh.authorizedKeys.keys = config.identity.authorizedKeys;

  services.openssh = {
    # Keep Remote Login under System Settings' control. Applying this policy
    # leaves it off when it is off, and preserves a later manual toggle.
    enable = lib.mkDefault null;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      PermitRootLogin no
      AllowUsers ${config.mainUser}

      # Use nix-darwin's AuthorizedKeysCommand; ignore keys in the user's home.
      AuthorizedKeysFile none
    '';
  };
}
