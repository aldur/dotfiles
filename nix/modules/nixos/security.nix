{ lib, ... }:
{
  security.sudo.enable = false;

  security.sudo-rs.enable = true;
  security.sudo-rs.wheelNeedsPassword = lib.mkDefault true;
  security.sudo-rs.execWheelOnly = true;
}
