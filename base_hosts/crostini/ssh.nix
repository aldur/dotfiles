# Shared by LXC and Baguette.
{ lib, ... }:
{
  imports = [ ../../modules/nixos/ssh-local-root.nix ];

  services.openssh = {
    # Each guest generates its host key on first boot and retains it in /persist.
    generateHostKeys = true;
    hostKeys = lib.mkForce [
      {
        type = "ed25519";
        path = "/persist/ssh/ssh_host_ed25519_key";
      }
    ];
  };

  # /persist can be supplied by the LXC host or live on the Baguette disk.
  # Wait for its mount before key generation if it is a separate filesystem.
  systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = [ "/persist/ssh" ];
}
