{ inputs, ... }:
{
  imports = [
    "${inputs.self}/base_hosts/appliance/desktop.nix"
    ./guest.nix
  ];
  networking.hostName = "browser-vm";
}
