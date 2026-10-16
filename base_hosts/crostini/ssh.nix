# Shared by LXC and Baguette. This boundary does not require a guest firewall.
{ lib, ... }:
{
  services.openssh = {
    openFirewall = lib.mkForce false;
    settings = {
      AllowUsers = lib.mkForce [ "root" ];
      AllowTcpForwarding = false;
      X11Forwarding = false;
      PermitRootLogin = lib.mkForce "prohibit-password";
      AuthenticationMethods = "publickey";
    };

    # Each guest generates its host key on first boot and retains it in /persist.
    generateHostKeys = true;
    hostKeys = lib.mkForce [
      {
        type = "ed25519";
        path = "/persist/ssh/ssh_host_ed25519_key";
      }
    ];
  };

  # Use systemd's /run/ssh-unix-local/socket via `ssh root@.host`.
  # Mask TCP and host-facing sockets; only guest-local access is allowed.
  systemd.services.sshd.enable = false;
  systemd.sockets = {
    sshd.enable = false;
    sshd-vsock = {
      enable = false;
      # Mask the unit itself, not the upstream NixOS drop-in.
      overrideStrategy = lib.mkForce "asDropinIfExists";
    };
    sshd-unix-export.enable = false;
  };

  # /persist can be supplied by the LXC host or live on the Baguette disk.
  # Wait for its mount before key generation if it is a separate filesystem.
  systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = [ "/persist/ssh" ];
}
