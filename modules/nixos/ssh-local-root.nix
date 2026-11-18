# SSH only for root and only from within the guest. Run `ssh root@.host` to
# connect through /run/ssh-unix-local/socket of systemd-ssh-generator. The
# host sets the authorized keys of root. This boundary does not require a
# guest firewall.
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
  };

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
}
