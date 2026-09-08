{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  authorizedKeys = pkgs.writeText "macos-${config.mainUser}-authorized_keys" (
    inputs.self.lib.authorizedKeysText config.identity.authorizedKeys
  );
in
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

      # Read root-managed keys directly; ignore keys in the user's home.
      AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
      AuthorizedKeysCommand none
    '';
  };

  # Install a root-owned file that the login user can read but cannot change.
  # Users can traverse the directory; only root can replace its entries.
  # The openssh activation phase runs before the sshd configuration is linked.
  system.activationScripts.openssh.text = lib.mkAfter ''
    /usr/bin/install -d -o root -g wheel -m 0755 /etc/ssh/authorized_keys.d
    /usr/bin/install -o root -g wheel -m 0644 ${authorizedKeys} \
      ${lib.escapeShellArg "/etc/ssh/authorized_keys.d/${config.mainUser}"}
  '';
}
