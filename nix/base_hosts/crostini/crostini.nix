{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
let
  username = "aldur";
  uid = 1000;
in
{
  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
    inputs.preservation.nixosModules.preservation
  ];

  hardware.graphics.enable = true;
  # Enable Wayland compatibility for Chrome and Electron apps.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

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
        IdentityAgent /run/user/${toString uid}/yubikey-agent/yubikey-agent.sock
    '';
  };

  # NOTE: It will use gnupg.agent.pinentryPackage
  services.yubikey-agent.enable = true;

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
        users = [ username ];
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

  home-manager.users.${username} =
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
      "size=4G"
      "mode=755"
    ];
  };

  preservation = {
    enable = true;

    preserveAt."/persist" = {
      users = {
        ${username} = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            ".local/state/nix" # Required by HM

            ".local/share/atuin"
            ".local/share/dasht"
            ".local/share/direnv"
            ".local/share/fish"

            "Documents/"
            "Work/"

            {
              directory = ".ssh";
              mode = "0700";
            }
          ]
          ++ lib.optional config.programs.aldur.lazyvim.enable ".local/state/lazyvim";

          files = lib.optional config.programs.aldur.claude-code.enable ".claude.json";
        };
      };
    };
  };

  systemd = {
    # This makes it so that `sommelier` can set `DISPLAY`,
    # which is then used by `pinentry`.
    user.services.yubikey-agent.after = [
      "sommelier@0.service"
      "sommelier@1.service"
      "sommelier-x@0.service"
      "sommelier-x@1.service"
    ];

    tmpfiles.settings.preservation =
      let
        defaultPermissions = {
          user = username;
          group = "users";
          mode = "0755";
        };
      in
      {
        "/home/${username}".d = defaultPermissions;
        "/home/${username}/.local".d = defaultPermissions;
        "/home/${username}/.local/share".d = defaultPermissions;
        "/home/${username}/.local/state".d = defaultPermissions;
      };

    # This is required because with tmpfs,
    # ~/.config/systemd/user/ is empty at boot,
    # hm activates and populates it, but
    # needs XDG_RUNTIME_DIR to know that `systemd` for
    # the user is running and let it learn about the new units.
    #
    # after/wants ensure that systemd for the user starts _before_ home
    # manager.
    #
    # This fixes the following log line in home-manager-aldur.service:
    # User systemd daemon not running. Skipping reload.
    #
    # It is possible this was a bug before, but tmpfs made it more promiment.
    services."home-manager-${username}" = {
      after = [ "user@${toString uid}.service" ];
      wants = [ "user@${toString uid}.service" ];
      environment = {
        XDG_RUNTIME_DIR = "/run/user/${toString uid}";
      };
    };
  };
}
