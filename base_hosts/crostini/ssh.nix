# Shared by LXC and Baguette. This boundary does not require a guest firewall.
{ config, lib, ... }:
{
  services.openssh = {
    openFirewall = lib.mkForce false;
    # Keep port 22: ChromeOS automatically tunnels some unprivileged ports.
    ports = lib.mkForce [ 22 ];
    startWhenNeeded = lib.mkForce false;
    listenAddresses = lib.mkForce (
      [ { addr = "127.0.0.1"; } ] ++ lib.optionals config.networking.enableIPv6 [ { addr = "::1"; } ]
    );
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

  # /persist can be supplied by the LXC host or live on the Baguette disk.
  # Wait for its mount before key generation if it is a separate filesystem.
  systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = [ "/persist/ssh" ];
}
