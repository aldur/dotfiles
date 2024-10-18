{
  description = "nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
    let
      user = "aldur";
      configuration = { pkgs, ... }:
        {
          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          nix.package = pkgs.nix;
          programs.nix-index.enable = true;

          nix.settings.allowed-users = [ user ];
          nix.settings.trusted-users = [ "root" ];
          nix.settings.sandbox = false;

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
              })
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
            gls = "ls --color=tty";
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

          environment.systemPackages = with pkgs;
            [
              age
              age-plugin-yubikey
              autossh
              bashInteractive
              bat
              blueutil
              cmake
              coreutils-prefixed
              curl
              diffstat
              exiftool
              fd
              fzf
              git
              git-crypt
              gnupg
              htop
              jq
              neovide
              neovim
              node2nix
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
            ] ++ [
              (pkgs.callPackage
                ../nix/packages/age-plugin-se/age-plugin-se.nix
                { }).age-plugin-se
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
