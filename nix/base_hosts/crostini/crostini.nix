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

    # We rely on the UID in a few places, so better making sure about it.
    users.users.${username}.uid = uid;

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

          # Signal completion of home-manager activation for impermanence.
          # Uses XDG_RUNTIME_DIR which is fresh each boot (tmpfs).
          activation.signalReady = lib.mkIf cfg.impermanence.enable (
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run touch "$XDG_RUNTIME_DIR/home-manager-ready"
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
        # This makes it so that `sommelier` can set `DISPLAY`,
        # which is then used by `pinentry`.
        yubikey-agent.after = [
          "sommelier@0.service"
          "sommelier@1.service"
          "sommelier-x@0.service"
          "sommelier-x@1.service"
        ];
      }
      // lib.optionalAttrs cfg.impermanence.enable {
        # Create a user service that waits for home-manager to complete setup.
        # This is needed because garcon (which spawns shells) starts immediately
        # when user systemd starts, but home-manager (a system service) runs
        # after user systemd starts and creates config symlinks. Without this,
        # fish starts before its config is properly linked.
        #
        # NOTE: Do NOT add wantedBy = [ "default.target" ] here!
        #
        # That would create a circular dependency:
        #   - is-system-running won't return "running" until default.target is reached
        #   - default.target requires all wantedBy services to complete
        #   - wait-for-home-manager waits for home-manager activation
        #   - home-manager checks is-system-running before reloading systemd units
        # Instead, let garcon pull this service in via `wants`.
        wait-for-home-manager = {
          description = "Wait for home-manager activation to complete";
          before = [ "garcon.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart =
              let
                markerFile = "/run/user/${toString uid}/home-manager-ready";
              in
              pkgs.writeShellScript "wait-for-home-manager" ''
                set -euo pipefail

                # Check if already ready (avoid race condition)
                if [[ -f "${markerFile}" ]]; then
                  exit 0
                fi

                # Use inotifywait to efficiently wait for the marker file
                ${pkgs.inotify-tools}/bin/inotifywait \
                  --timeout 30 \
                  --event create \
                  --include 'home-manager-ready$' \
                  /run/user/${toString uid}/ || {
                    # Check one more time in case of race
                    if [[ -f "${markerFile}" ]]; then
                      exit 0
                    fi
                    echo "Timeout waiting for home-manager activation" >&2
                    exit 1
                  }
              '';
          };
        };

        # Make garcon wait for home-manager to complete.
        # `wants` pulls in wait-for-home-manager, `after` ensures ordering.
        garcon = {
          after = [ "wait-for-home-manager.service" ];
          wants = [ "wait-for-home-manager.service" ];
        };
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

      # This is required because with tmpfs,
      # ~/.config/systemd/user/ is empty at boot,
      # hm activates and populates it, but
      # needs XDG_RUNTIME_DIR to know that `systemd` for
      # the user is running and let it learn about the new units.
      #
      # after/wants ensure that systemd for the user starts _before_ home
      # manager.
      #
      # ExecStartPre waits for user systemd to be responsive (can accept commands).
      # We check this by running a simple systemctl command, NOT by waiting for
      # is-system-running to return "running"/"degraded" - that would create a
      # circular dependency with wait-for-home-manager.service (a user service
      # that waits for home-manager to create config symlinks).
      services."home-manager-${username}" = lib.mkIf cfg.impermanence.enable {
        after = [ "user@${toString uid}.service" ];
        wants = [ "user@${toString uid}.service" ];
        environment = {
          XDG_RUNTIME_DIR = "/run/user/${toString uid}";
        };
        serviceConfig = {
          ExecStartPre = pkgs.writeShellScript "wait-for-user-systemd" ''
            set -euo pipefail
            for i in {1..30}; do
              if XDG_RUNTIME_DIR=/run/user/${toString uid} \
                 ${pkgs.systemd}/bin/systemctl --user list-units --no-pager >/dev/null 2>&1; then
                exit 0
              fi
              sleep 1
            done
            echo "Timeout waiting for user systemd to be responsive" >&2
            exit 1
          '';
        };
      };
    };
  };
}
