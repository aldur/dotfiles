{
  pkgs,
  config,
  inputs,
  ...
}:
{
  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
  ];
  hardware.graphics.enable = true;

  programs = {

    aldur.lazyvim.enable = true;
    aldur.lazyvim.packageNames = [ "lazyvim" ];
    gnupg.agent.pinentryPackage = pkgs.pinentry-qt;

    # This configures default SSH connections (including those initiated by
    # root when using a remote builder) to go through yubikey-agent.
    ssh.extraConfig = ''
      Host *
        IdentityAgent /run/user/1000/yubikey-agent/yubikey-agent.sock
    '';
  };

  services.yubikey-agent.enable = true;

  # This makes it so that `sommelier` can set `DISPLAY`,
  # which is then used by `pinentry`.
  systemd.user.services.yubikey-agent.after = [
    "sommelier@0.service"
    "sommelier@1.service"
    "sommelier-x@0.service"
    "sommelier-x@1.service"
  ];

  # Make it possible to use remote builders under this username
  nix.settings.trusted-users = [ config.users.users.aldur.name ];

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      mode = "0600";
      source = ./ssh_host_ed25519_key;
    };
    "ssh/ssh_host_ed25519_key.pub" = {
      mode = "0644";
      source = ./ssh_host_ed25519_key.pub;
    };
  };
  services.openssh.settings.AllowUsers = [ "root" ];

  security = {
    pam.sshAgentAuth.enable = false;
    pam.sshAgentAuth.authorizedKeysFiles = [
      "/etc/ssh/authorized_keys.d/root"
    ];

    # NOTE: There a bug (maybe) in pcscd where, when running in an lxc container,
    # it doesn't automatically exit when the "smart card" is disconnected.
    #
    # When a new smart card is connected (i.e., the security key is re-attached
    # to the container), it will fail to detect it and the SSH agent won't
    # work. The fix is easy: you just need to restart pcscd. But it requires
    # sudo privileges and the `aldur` user has no password.
    sudo-rs.extraRules = [
      {
        users = [ "aldur" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl restart pcscd.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  # Enable SSH root login through localhost
  users.users.root.openssh.authorizedKeys.keys = pkgs.callPackage ../../utils/github-keys.nix { };

  home-manager.users.aldur =
    { config, ... }: # home-manager's config, not the OS one
    {
      home.packages = with pkgs; [
        age-plugin-yubikey
        yubikey-manager
      ];
    };
}
