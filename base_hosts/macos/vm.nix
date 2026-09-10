{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  ownerKeys = pkgs.writeText "macos-vm-owner-keys" (
    inputs.self.lib.authorizedKeysText inputs.self.utils.github-keys
  );
in
{
  # Keep the prepared image's UID 501 account; all shared dotfiles use mainUser.
  mainUser = "admin";
  networking.hostName = "macos-vm";
  services.openssh.enable = true;
  security.pam.services.sudo_local.touchIdAuth = lib.mkForce false;
  security.pam.services.sudo_local.reattach = lib.mkForce false;
  home-manager.users.admin.services.yubikey-agent.enable = lib.mkForce false;

  # The per-VM public key is installed by the launcher before activation.
  # Keep it out of the system derivation so each launch can use its own identity.
  services.openssh.extraConfig = lib.mkForce ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    AuthenticationMethods publickey
    PermitRootLogin no
    AllowUsers admin
    AuthorizedKeysFile /etc/ssh/macos-vm-authorized-key ${ownerKeys}
    AuthorizedKeysCommand none
  '';
  # New nix-darwin versions reject the legacy directory used by the shared
  # activation snippet. The VM reads the immutable owner key file directly.
  system.activationScripts.openssh.text = lib.mkForce "";
}
