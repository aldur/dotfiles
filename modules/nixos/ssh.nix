# NOTE: SSH keys are configured per user.
{ config, ... }:
{
  imports = [ ./ssh-policy.nix ];

  services.openssh.settings = {
    AllowUsers = [ config.mainUser ];
    LogLevel = "VERBOSE";
  };
}
