# NOTE: SSH keys are configured per user.
{ config, ... }:
{
  services.openssh = {
    enable = true;
    allowSFTP = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ config.users.users.aldur.name ];
    };
  };
}
