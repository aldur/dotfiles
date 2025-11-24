{ lib, ... }:
{
  security = {
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      wheelNeedsPassword = lib.mkDefault true;
      execWheelOnly = true;
    };
  };
}
