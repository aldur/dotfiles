{
  description = "nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOTE: This input is locked. That means that if you update `tiktoken`,
    # you'll need to update its lock as well for changes to be fetched.
    # Might be better to restructure `tiktoken` to import it with `import`.
    # See: https://github.com/NixOS/nix/issues/3978
    tiktoken = {
      url = "git+file:.?dir=nix/packages/tiktoken";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      tiktoken,
      ...
    }:
    let
      user = "aldur";
      configuration =
        { pkgs, ... }:
        {
          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          nix.package = pkgs.nix;
          programs.nix-index.enable = true;

          nix.settings.allowed-users = [ user ];
          nix.settings.trusted-users = [ "root" ];
          nix.settings.sandbox = false;

          # Not working on macOS?
          # nix.extraOptions = ''
          #   plugin-files = ${pkgs.nix-doc}/lib/libnix_doc_plugin.so
          # '';

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility. please read the changelog
          # before changing: `darwin-rebuild changelog`.
          system.stateVersion = 4;

          nixpkgs = {
            # The platform the configuration will be used on.
            # If you're on an Intel system, replace with "x86_64-darwin"
            hostPlatform = "aarch64-darwin";

            overlays = [
              (final: prev: {
                neovim = (prev.callPackage ../neovim/neovim.nix { });
                neovim-vanilla = prev.neovim;
              })
              tiktoken.overlays.default
            ];

            # config.allowUnsupportedSystem = true;
          };

          # Declare the user that will be running `nix-darwin`.
          # NOTE: This won't be executed if the user already exists.
          users.users.${user} = {
            name = user;
            home = "/Users/${user}";
            shell = pkgs.fish;
          };

          environment.variables = {
            EDITOR = "nvim";

            LANG = "en_US.UTF-8";
            LC_CTYPE = "en_US.UTF-8";

            # https://esham.io/2023/10/direnv
            DIRENV_LOG_FORMAT = ''$(printf "\033[2mdirenv: %%s\033[0m")'';

            # Override macOS ssh-agent with Secretive (installed from `brew`)
            SSH_AUTH_SOCK = "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
            AUTOSSH_PORT = "0";

            HOMEBREW_NO_INSECURE_REDIRECT = "1";
            HOMEBREW_CASK_OPTS = "--require-sha";
            HOMEBREW_NO_AUTO_UPDATE = "1";
            HOMEBREW_NO_ANALYTICS = "1";

            FZF_DEFAULT_OPTS = "--bind alt-p:toggle-preview";
            FZF_DEFAULT_COMMAND = "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global";
            FZF_ALT_C_COMMAND = "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global --type d";
            FZF_CTRL_T_COMMAND = "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global";

            RIPGREP_CONFIG_PATH = "/Users/${user}/.ripgreprc";

            PAGER = "less -R";
            MANPAGER = "nvim +Man!";

            VIRTUAL_ENV_DISABLE_PROMPT = "1";
          };

          environment.shellAliases = {
            gst = "git status";
            gp = "git push";
            gss = "git switch $(git branch -r | fzf | sed 's|origin/||' | xargs)";
            gc = "git commit";

            ls = "ls --color=tty";

            ssh = "autossh";

            ta = "tmux -CC new -ADs";
            tls = "tmux ls";

            vim = "neovide";
            neovide = "'/Applications/Nix Apps/Neovide.app/Contents/MacOS/neovide_server.sh'";
          };

          programs.bash.enable = true;
          programs.zsh.enable = true;

          # See
          # https://github.com/LnL7/nix-darwin/issues/122#issuecomment-1782971499
          # if this doesn't work at first
          programs.fish.enable = true;

          programs.direnv.enable = true;
          programs.direnv.nix-direnv.enable = true;

          environment.systemPackages =
            with pkgs;
            [
              age
              age-plugin-yubikey
              autossh
              bashInteractive
              bat
              blueutil
              coreutils-prefixed
              curl
              difftastic
              exiftool
              fd
              fzf
              git
              git-crypt
              gnupg
              htop
              jq
              less
              neovim
              nix-doc
              ollama
              pandoc
              pinentry_mac
              poetry
              pv
              python3
              reattach-to-user-namespace
              rig
              ripgrep
              ripgrep-all
              tmux
              tree
              universal-ctags
              watch
              yubikey-agent
            ]
            ++ [
              (neovide.override {
                # Only used for checks
                neovim = neovim-vanilla;
              })
            ]
            ++ [
              (pkgs.callPackage ../nix/packages/age-plugin-se/age-plugin-se.nix { }).age-plugin-se
            ]
            ++ [
              count-tokens
            ];

          security.pam.enableSudoTouchIdAuth = true;

          homebrew = {
            enable = true;
            onActivation.cleanup = "zap";

            caskArgs.no_quarantine = true;
            caskArgs.require_sha = true;

            taps = [
              "homebrew/services"
            ];
            brews = [
              {
                name = "syncthing";
                start_service = true;
                restart_service = "changed";
              }
            ];
            casks = import ./casks.nix;
            masApps = import ./masApps.nix;
          };

          launchd = {
            user = {
              agents = {
                ollama = {
                  command = "${pkgs.ollama}/bin/ollama serve";
                  serviceConfig = {
                    KeepAlive = true;
                    RunAtLoad = true;
                  };
                };
              };
            };
          };

          system.defaults = {
            dock.autohide = true;
            dock.autohide-delay = 0.0;
            dock.autohide-time-modifier = 0.15;
            dock.mru-spaces = false;

            finder.AppleShowAllExtensions = true;
            # Do not warn on changing file extension
            finder.FXEnableExtensionChangeWarning = false;

            finder.FXPreferredViewStyle = "clmv";

            screencapture.location = "~/Documents/Screenshots";

            screensaver.askForPassword = true;
            screensaver.askForPasswordDelay = 0;

            NSGlobalDomain.AppleInterfaceStyle = "Dark";
            NSGlobalDomain.InitialKeyRepeat = 10;
            NSGlobalDomain.KeyRepeat = 1;

            CustomSystemPreferences = {
              "com.apple.AppleMultitouchTrackpad" = {
                "TrackpadThreeFingerDrag" = true;
              };
              "com.apple.menuextra.clock" = {
                "DateFormat" = "\"d MMM HH:mm:ss\"";
              };
              "com.apple.desktopservices" = {
                # Avoid creating .DS_Store files on network or USB volumes
                DSDontWriteNetworkStores = true;
                DSDontWriteUSBStores = true;
              };
              "com.apple.AdLib" = {
                allowApplePersonalizedAdvertising = false;
              };
              "com.apple.SoftwareUpdate" = {
                AutomaticCheckEnabled = true;
                # Check for software updates daily, not just once per week
                ScheduleFrequency = 1;
                # Download newly available updates in background
                AutomaticDownload = 1;
                # Install System data files & security updates
                CriticalUpdateInstall = 1;
              };
              # Turn on app auto-update
              "com.apple.commerce".AutoUpdate = true;
            };
          };
          system.activationScripts.postUserActivation.text = ''
            # Following line should allow us to avoid a logout/login cycle
            /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
          '';
        };
    in
    {
      darwinConfigurations.Maui = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
        ];
      };
    };
}
