{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
    inputs.preservation.nixosModules.preservation
  ];
  hardware.graphics.enable = true;

  programs = {
    aldur = {
      lazyvim.enable = true;
      lazyvim.packageNames = [ "lazyvim" ];
      claude-code.enable = true;
    };

    gnupg.agent.pinentryPackage = pkgs.pinentry-qt;

    # This configures default SSH connections (including those initiated by
    # root when using a remote builder) to go through yubikey-agent.
    ssh.extraConfig = ''
      Host *
        IdentityAgent /run/user/1000/yubikey-agent/yubikey-agent.sock
    '';
  };

  # NOTE: It will use gnupg.agent.pinentryPackage
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
  # nix.settings.trusted-users = [ config.users.users.aldur.name ];

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
  users.users.root.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;

  home-manager.users.aldur =
    { config, ... }: # home-manager's config, not the OS one
    {
      home.packages = with pkgs; [
        age-plugin-yubikey
        yubikey-manager
      ];

      programs.llm.enable = true;
    };

  boot.initrd.systemd.enable = true;

  fileSystems."/home" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=2G"
      "mode=755"
    ];
  };

  preservation = {
    enable = true;

    preserveAt."/persist" = {
      # preserve user-specific files, implies ownership
      users = {
        aldur = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            ".local/state/lazyvim"
            ".local/share/direnv"
          ];
          files = [
            ".ssh/known_hosts"
          ];
        };
      };
    };
  };

  # Create some directories with custom permissions.
  #
  # In this configuration the path `/home/butz/.local` is not an immediate parent
  # of any persisted file, so it would be created with the systemd-tmpfiles default
  # ownership `root:root` and mode `0755`. This would mean that the user `butz`
  # could not create other files or directories inside `/home/butz/.local`.
  #
  # Therefore systemd-tmpfiles is used to prepare such directories with
  # appropriate permissions.
  #
  # Note that immediate parent directories of persisted files can also be
  # configured with ownership and permissions from the `parent` settings if
  # `configureParent = true` is set for the file.
  systemd.tmpfiles.settings.preservation = {
    "/home/aldur/.local".d = {
      user = "aldur";
      group = "users";
      mode = "0755";
    };
    "/home/aldur/.local/share".d = {
      user = "aldur";
      group = "users";
      mode = "0755";
    };
    "/home/aldur/.local/state".d = {
      user = "aldur";
      group = "users";
      mode = "0755";
    };
  };
}
