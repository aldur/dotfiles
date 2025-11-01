{
  description = "nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };

    nixCats.url = "github:BirdeeHub/nixCats-nvim";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, nix-homebrew, nix-rosetta-builder
    , nix-index-database, ... }@inputs:
    let
      user = "aldur";
      system = "aarch64-darwin";

      # https://wiki.nixos.org/wiki/Nixpkgs/Patching_Nixpkgs
      pkgs' = config: pkgs:
        (import nixpkgs {
          inherit system;
          nixpkgs.config.allowUnfreePredicate = (pkg:
            builtins.elem (pkgs.lib.getName pkg)
            config.nixpkgs.allowUnfreeByName);
        }).applyPatches {
          name = "nixpkgs-patched";
          src = nixpkgs;
          patches = [
            # (builtins.fetchurl {
            #   url = "https://github.com/NixOS/nixpkgs/pull/404770.patch";
            #   sha256 = "sha256:0bkrd8dg7f5q8fyw8z390pfywmkjnsd9xxcwnybsgchhj02rk3pw";
            # })
          ];
        };

      configuration = { cfg, pkgs, ... }:
        let python3 = pkgs.python3;
        in {
          imports = [
            ../nix/modules/darwin
            ../nix/modules/development.nix
            ../nix/modules/direnv.nix
            ../nix/modules/environment.nix
            ../nix/modules/fish.nix
            ../nix/modules/nix.nix
            ../nix/modules/nix_search.nix
            ../nix/modules/users.nix
          ];

          system.primaryUser = user;

          _module.args = { inherit user system inputs; };

          programs.better-nix-search.enable = true;
          programs.syncthing.enable = true;
          programs.ollama.enable = false;
          programs.open-webui.enable = false;

          system.configurationRevision = self.rev or self.dirtyRev or null;

          # See: https://github.com/nix-darwin/nix-darwin/issues/1307
          nix.optimise.automatic = pkgs.lib.mkForce false;
          nix.gc.automatic = pkgs.lib.mkForce false;
          nix.settings.auto-optimise-store = pkgs.lib.mkForce false;

          nixpkgs = {
            overlays = [
              (import ./overlays/neovide.nix)
              (import ./overlays/neovim.nix)
              (import ./overlays/lazyvim.nix { inherit inputs pkgs; })
              (import ./overlays/zeal.nix)
              (import ../nix/overlays/packages.nix)
              (final: prev: {
                # FIXME: Broken on macOS
                # https://github.com/NixOS/nixpkgs/pull/392430/files
                pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
                  (python-final: python-prev: {
                    pgvector = python-prev.pgvector.overridePythonAttrs
                      (oldAttrs: {
                        doCheck = false;
                        nativeCheckInputs = [ ];
                      });
                  })
                ];
              })
            ];

            # NOTE: No need to set `hostPlatform` since we set `pkgs`.
            pkgs = import (pkgs' cfg pkgs) { inherit system; };
          };

          environment.variables = {
            EDITOR = "nvim";

            LANG = "en_US.UTF-8";
            LC_CTYPE = "en_US.UTF-8";

            # Override macOS ssh-agent with Secretive (installed from `brew`)
            SSH_AUTH_SOCK =
              "$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
            AUTOSSH_PORT = "0";

            FZF_DEFAULT_OPTS = "--bind alt-p:toggle-preview";
            FZF_DEFAULT_COMMAND =
              "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global";
            FZF_ALT_C_COMMAND =
              "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global --type d";
            FZF_CTRL_T_COMMAND =
              "fd -d 10 --hidden --follow --exclude .git --exclude .svn --ignore-file ~/.gitignore_global";

            RIPGREP_CONFIG_PATH = "/Users/${user}/.ripgreprc";

            PAGER = "less -R";
            MANPAGER = "nvim +Man!";

            VIRTUAL_ENV_DISABLE_PROMPT = "1";
          };

          # macOS-specific aliases
          environment.shellAliases = {
            ssh = "autossh";

            vim = "nvim";
            neovide = "open -a Neovide";

            tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";

            faraday =
              "sandbox-exec -p '(version 1)(allow default)(deny network*)'";
            sandbox =
              "sandbox-exec -p '(version 1)(allow default)(deny network*)(deny file-read-data (regex \"^/Users/'$USER'/(Documents|Desktop|Developer|Movies|Music|Pictures)\"))'";
          };

          programs.bash.enable = true;
          programs.zsh.enable = true;

          programs.fish.interactiveShellInit = ''
            ${pkgs.lib.getExe pkgs.atuin} init fish | source
          '';

          environment.systemPackages = with pkgs;
            [
              # macOS-specific
              atuin # Until we use home manager
              fzf # Until we use home manager
              age-plugin-yubikey
              blueutil
              git-crypt
              gnupg
              ollama

              # llm
              (python312.withPackages
                (ps: [ ps.llm ps.llm-ollama ps.llm-gguf llm-mlx ]))
              strip-tags
              files-to-prompt
              # /llm

              pandoc
              pinentry_mac
              python3
              rig
              ffmpeg
              exiftool
              reattach-to-user-namespace
              syncthing
              yubikey-agent
              age-plugin-se
            ] ++ [
              # GUI from nix
              golden-cheetah-bin
              # zeal-qt6
              maccy
            ] ++ [
              # nvim
              neovim
              neovide
              lazyvim
            ] ++ [
              # bundled packages
              tiktoken
              llmcat
            ];
        };
    in {
      darwinConfigurations.Maui = nix-darwin.lib.darwinSystem {
        modules = [
          configuration

          nix-homebrew.darwinModules.nix-homebrew
          nix-index-database.darwinModules.nix-index

          # An existing Linux builder is needed to initially bootstrap `nix-rosetta-builder`.
          # If one isn't already available: comment out the `nix-rosetta-builder` module below,
          # uncomment this `linux-builder` module, and run `darwin-rebuild switch`:
          # { nix.linux-builder.enable = true; }
          # Then: uncomment `nix-rosetta-builder`, remove `linux-builder`, and `darwin-rebuild switch`
          # a second time. Subsequently, `nix-rosetta-builder` can rebuild itself.
          nix-rosetta-builder.darwinModules.default
          {
            # see available options in module.nix's `options.nix-rosetta-builder`
            nix-rosetta-builder.onDemand = true;
          }
        ];
      };
    };
}
