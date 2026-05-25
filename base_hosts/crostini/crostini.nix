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
  cfg = config.crostini;
in
{
  options.crostini = {
    impermanence = {
      enable = lib.mkEnableOption "tmpfs home with preservation";
      persist.claude-code = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.aldur.claude-code.enable;
        description = "Whether to persist Claude Code state and credentials";
      };
    };
  };

  imports = [
    "${inputs.self}/modules/current_system_flake.nix"
    "${inputs.self}/modules/nixos/pragmatism.nix"
    "${inputs.self}/modules/nixos/preservation-system.nix"
    "${inputs.self}/modules/nixos/preservation-user.nix"
    inputs.preservation.nixosModules.preservation
  ];

  config = {
    crostini.impermanence.enable = lib.mkDefault true;
    users.users = {
      # We rely on the UID in a few places, so better making sure about it.
      ${username} = {
        inherit uid;
        # Start user@1000.service at boot (independent of PAM login).
        # This allows us to order it after home-manager.
        linger = cfg.impermanence.enable;

        # Make sure user has no password.
        initialHashedPassword = lib.mkForce null;
      };

      # Make sure root has no password.
      root.initialHashedPassword = lib.mkForce null;

      # Enable SSH root login through localhost
      root.openssh.authorizedKeys.keys = inputs.self.utils.github-keys;
    };

    hardware.graphics.enable = true;
    # Enable Wayland compatibility for Chrome and Electron apps.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    programs = {
      aldur = {
        lazyvim.enable = true;
        lazyvim.packageNames = [ "lazyvim" ];
        claude-code.enable = true;
        # The hooks defined below in home-manager invoke notify-send when
        # Claude finishes or needs input; that requires the session bus
        # path through the sandbox to org.freedesktop.Notifications.
        claude-code.sandbox.extraDbusTalk = [ "org.freedesktop.Notifications" ];
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

    home-manager.users.${username} =
      { config, lib, ... }: # home-manager's config, not the OS one
      {
        programs = {
          llm = {
            enable = true;
          };
          better-nix-search.enable = true;
          claude-code.writableSettings.hooks = {
            Stop = [
              {
                matcher = "";
                hooks = [
                  {
                    type = "command";
                    command = "${pkgs.libnotify}/bin/notify-send 'Claude' 'Done'";
                  }
                ];
              }
            ];
            Notification = [
              {
                matcher = "";
                hooks = [
                  {
                    type = "command";
                    command = "${pkgs.libnotify}/bin/notify-send 'Claude' 'Needs input'";
                  }
                ];
              }
            ];
          };
        };
        home = {
          packages = with pkgs; [
            age-plugin-yubikey
            yubikey-manager
          ];
        };

        # The NixOS module's standalone unit is hardened and survives a rebuild
        # cleanly; HM's socket-activated variant double-binds the socket path
        # (yubikey-agent ignores LISTEN_FDS and rebinds via `-l`) and leaves it
        # in a broken state after sd-switch SIGTERMs the service. The NixOS
        # module only sets SSH_AUTH_SOCK via /etc/profile (bash-only), so we
        # set it through home.sessionVariables so fish picks it up too.
        services.yubikey-agent.enable = lib.mkForce false;
        home.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR:-/run/user/$UID}/yubikey-agent/yubikey-agent.sock";
      };

    boot.initrd.systemd.enable = cfg.impermanence.enable;

    # Impermanence: tmpfs home with preservation
    fileSystems."/home" = lib.mkIf cfg.impermanence.enable {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
    };

    preservation = lib.mkIf cfg.impermanence.enable {
      enable = true;
    };

    # Host-key + machine-id persistence is intentionally off here: crostini
    # already installs a checked-in ssh_host_ed25519_key via
    # environment.etc, and bind-mounting /persist/etc/ssh/... on top of
    # that /nix/store-backed symlink doesn't work. Revisit as its own
    # change, coordinated with removing the environment.etc entries.
    aldur.preservation-system.enable = false;
    aldur.preservation-user = {
      enable = cfg.impermanence.enable;
      inherit username;
      persistClaudeCode =
        cfg.impermanence.persist.claude-code && config.programs.aldur.claude-code.enable;
    };

    systemd = {
      user.services = {
        # This ensures that `sommelier` sets `DISPLAY`, used by `pinentry`.
        yubikey-agent.after = [
          "sommelier@0.service"
          "sommelier@1.service"
          "sommelier-x@0.service"
          "sommelier-x@1.service"
        ];
        # Don't start a yubikey-agent instance for root.
        yubikey-agent.unitConfig.ConditionUser = "!root";
      };

    };
  };
}
