# Standalone SSH policy: no user accounts or Home Manager configuration.
{ lib, ... }:
{
  services.openssh = {
    enable = lib.mkDefault true;
    allowSFTP = lib.mkDefault false;
    # Only root-managed users.users.<name>.openssh.authorizedKeys are trusted.
    authorizedKeysInHomedir = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
