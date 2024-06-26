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
      configuration = { pkgs, ... }:
        let
          devPackages = with pkgs; [
            astyle
            beancount
            bibtool
            black
            cargo
            deno
            dockerfile-language-server-nodejs
            dotenv-linter
            efm-langserver
            hadolint
            html-tidy
            libxml2
            ltex-ls
            lua-language-server
            luarocks
            luaformatter
            marksman
            # mermaid-filter # TODO
            mdl
            nil
            nixpkgs-fmt
            pgformatter
            pyright
            ripgrep
            rust-analyzer
            shfmt
            solc
            sqlint
            terraform-ls
            texlab
            tflint
            vale
            vim-vint
            vim-language-server
            vscode-langservers-extracted
            typescript
            yamlfix
            yamllint
            yaml-language-server

            luaPackages.luacheck

            python312Packages.cfn-lint
            python312Packages.pynvim
            python312Packages.pyflakes
            python312Packages.python-lsp-server

            nodePackages.prettier
            # nodePackages.prettier-plugin-solidity
            nodePackages.sql-formatter
            nodePackages.typescript-language-server

            # Install through `pip`
            # timefhuman
          ] ++ [
            (import
              ../nix/packages/solhint/default.nix
              { inherit pkgs; }).solhint

            # TODO
            # (import
            #   ../nix/packages/mermaid-filter/default.nix
            #   { inherit pkgs; }).mermaid-filter
          ];
        in
        {
          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          nix.package = pkgs.nix;

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility. please read the changelog
          # before changing: `darwin-rebuild changelog`.
          system.stateVersion = 4;

          # The platform the configuration will be used on.
          # If you're on an Intel system, replace with "x86_64-darwin"
          nixpkgs.hostPlatform = "aarch64-darwin";

          # nixpkgs.config.allowUnsupportedSystem = true;

          # Declare the user that will be running `nix-darwin`.
          # NOTE: This won't be executed if the user already exists.
          users.users.aldur = {
            name = "aldur";
            home = "/Users/aldur";
            shell = pkgs.fish;
          };

          environment.variables = {
            EDITOR = "nvim";
          };

          programs.zsh.enable = true;

          # See https://github.com/LnL7/nix-darwin/issues/122#issuecomment-1782971499
          # if this doesn't work at first
          programs.fish.enable = true;

          environment.systemPackages = with pkgs; [
            age
            age-plugin-yubikey
            autossh
            bat
            blueutil
            cmake
            curl
            diff-so-fancy
            exiftool
            fd
            fzf
            gnupg
            htop
            jq
            neovim
            node2nix
            pandoc
            pinentry_mac
            pv
            python3
            reattach-to-user-namespace
            rig
            ripgrep
            ripgrep-all
            tmux
            tree
            universal-ctags
          ] ++ devPackages;

          security.pam.enableSudoTouchIdAuth = true;

          homebrew = {
            enable = true;
            # onActivation.cleanup = "uninstall";

            caskArgs.no_quarantine = true;
            caskArgs.require_sha = true;

            taps = [
              "remko/age-plugin-se"
              "shopify/shopify"
            ];
            brews = [
              "age-plugin-se"
              "theme-check"

              {
                name = "syncthing";
                start_service = true;
                restart_service = "changed";
              }
            ];
            casks = [
              "appcleaner"
              "bruno"  # nix pkgs does not currently build on macOS
              "calibre"
              "dash"
              "disk-inventory-x"
              "font-fira-code-nerd-font"
              "google-chrome"
              "hammerspoon"
              "iterm2"
              "karabiner-elements"
              "secretive"
              "slack"
              "stats"
              "tailscale"
              "the-unarchiver"
              "vlc"
            ];
            masApps = {
              "Drafts" = 1435957248;
              "Things" = 904280696;
            };
          };
        };
    in
    {
      darwinConfigurations.Ares = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
        ];
      };
    };
}
