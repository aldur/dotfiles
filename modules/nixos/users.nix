{ config, ... }:
{
  users.users.${config.mainUser} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    homeMode = "700";
  };

  users.mutableUsers = false;
}
