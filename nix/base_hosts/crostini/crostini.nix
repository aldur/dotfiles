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

        programs.llm.enable = true;
        home = {
          packages = with pkgs; [
            age-plugin-yubikey
            yubikey-manager
          ];

          # Ensure .claude.json has valid JSON content (instead of an empty file)
          activation.fixClaudeJson =
            lib.mkIf (cfg.impermanence.enable && cfg.impermanence.persist.claude-code)
              (
                lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  if [[ ! -s "$HOME/.claude.json" ]]; then
                    run echo '{}' > "$HOME/.claude.json"
                  fi
                ''
              );
        };
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

      preserveAt."/persist" = {
        users = {
          ${username} = {
            commonMountOptions = [
              "x-gvfs-hide"
            ];
            directories = [
              ".local/state/nix" # Required by HM
              ".local/state/lazygit"

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
            ++ lib.optional config.programs.aldur.lazyvim.enable ".local/state/lazyvim"
            ++ lib.optional (
              cfg.impermanence.persist.claude-code && config.programs.aldur.claude-code.enable
            ) ".claude";

            files = lib.optional (
              cfg.impermanence.persist.claude-code && config.programs.aldur.claude-code.enable
            ) ".claude.json";
          };
        };
      };
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
      };

      # Drop-in to make user@.service wait for home-manager.
      # This ensures the following order, important to make /home under tmpfs work:
      #
      # 1. System boots, linger-users.service enables linger for aldur
      # 2. `user@1000.service` starts but waits (due to `After=home-manager-aldur.service`)
      # 3. `home-manager-aldur.service` runs, creating user config (including `fish`)
      #    and hm service definitions
      # 4. `user@1000.service proceeds` (starting hm services)
      # 5. User services start; `garcon` starts `fish` with the correct configuration
      services."user@" = lib.mkIf cfg.impermanence.enable {
        overrideStrategy = "asDropin";
        after = [ "home-manager-${username}.service" ];
        wants = [ "home-manager-${username}.service" ];

        # In case something goes wrong, start `user` and transitively `garcon` after a timeout
        serviceConfig.TimeoutStartSec = "90";
      };

      tmpfiles.settings = lib.mkIf cfg.impermanence.enable {
        preservation =
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
      };

    };
  };
}
