{ pkgs, ... }:
{
  environment = {
    etc."dict.conf".text = "server dict.org";
    systemPackages = with pkgs; [ dict ];
  };
}
