{
  pkgs,
  inputs,
  stateVersion,
  lib,
  config,
  osConfig,
  ...
}:
let
  gpgKeys = pkgs.fetchurl {
    url = "https://github.com/aldur.gpg";
    sha256 = "sha256-x1H++Oqax/ZacnsTgurRFWI9I+/E7wb5pj8PXf7fhmw=";
  };
in
{
  imports = [
    inputs.clipshare.homeManagerModules.default
    ./dash.nix
    ./w3m.nix
    ./direnv.nix
    ./manpager.nix
    ./llm.nix
    ./nix_search.nix
    ./qemu-vm.nix
  ];

  home = {
    inherit stateVersion;

    username = "aldur";
    packages = with pkgs; [
      flake-lock-cooldown
      flatten-pdf
      fps
      gpg-encrypt
      moreutils
      shrinkpdf
    ];

    file."Documents/Notes/.marksman.toml".text = "";
  };

  programs = {
    clipshare.enable = true;

    claude-code = lib.optionalAttrs osConfig.programs.aldur.claude-code.enable {
      inherit (osConfig.programs.aldur.claude-code) enable;

      settings = {
        theme = "dark";
      };
    };

    fish = {
      enable = true;

      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        set -g fish_key_bindings fish_hybrid_key_bindings
      '';

      functions = {
        fish_hybrid_key_bindings = {
          description = "Vi-style bindings that inherit emacs-style bindings in all modes";
          body = ''
            for mode in default insert visual
                fish_default_key_bindings -M $mode
            end
            fish_vi_key_bindings --no-erase

            # https://github.com/fish-shell/fish-shell/issues/11082
            bind -M insert ctrl-n down-or-search
          '';
        };

        pyshell = {
          description = "Launch a nix shell with Python packages";
          body = ''
            if test (count $argv) -eq 0
                echo "Usage: pyshell <package1> [package2] ..."
                return 1
            end

            set -l packages (string join " " $argv)
            nix-shell -p "python3.withPackages (ps: with ps; [ $packages ])" --run "$SHELL"
          '';
        };

        fixssh = {
          # https://stackoverflow.com/a/34683596
          description = "Fix SSH socket in tmux after re-attaching";
          body = ''
            tmux show-env | grep '^SSH_' | while read -d= key val; set -gx $key $val; end
          '';
        };

      };

      plugins = [
        {
          name = "z";
          src = pkgs.fishPlugins.z;
        }
      ];
    };

    pet = {
      enable = true;
    };

    nh.enable = true;

    lazygit = {
      enable = true;
      enableFishIntegration = true;

      settings = {
        git = {
          autoFetch = false;
        };
      };
    };

    difftastic = {
      # enabled by default for `git diff`
      # enabled with `--ext-diff` to git show and git log -p
      enable = true;

      git.enable = true;
      git.diffToolMode = false;
    };

    git = {
      enable = true;

      settings = lib.recursiveUpdate (import ../shared/programs/git.nix) {
        user = {
          name = "aldur";
          email = "aldur@users.noreply.github.com";
        };

        commit.verbose = true;
        commit.gpgsign = true;
        tag.gpgsign = true;
        tag.forceSignAnnotated = true;
        gpg.format = "ssh";

        # NOTE: This will default to the _second_ key offered by the agent.
        gpg.ssh.defaultKeyCommand = lib.mkDefault "sh -c 'echo key::$(ssh-add -L | tail -n 1)'";
      };
    };

    # Let Home Manager install and manage itself.
    home-manager.enable = true;

    atuin = {
      enable = true;
      daemon.enable = true;
      settings = {
        enter_accept = false;
      };
    };

    fzf = {
      enable = true;
    };

    tmux = (import ../shared/programs/tmux.nix { inherit pkgs; }) // {
      enable = true;
      prefix = "c-a";
      mouse = true;
      focusEvents = true;
    };

    gpg = {
      enable = true;
      scdaemonSettings = {
        # https://blog.apdu.fr/posts/2024/12/gnupg-and-pcsc-conflicts-episode-3/
        pcsc-shared = true;

        # https://support.yubico.com/s/article/Resolving-GPGs-CCID-conflicts
        disable-ccid = true;
      };
      publicKeys = [
        {
          source = "${gpgKeys}";
          trust = "ultimate";
        }
      ];
    };
  };

  # NOTE: Pinentry configured by each respective module
  services.gpg-agent.enable = true;

  home.shellAliases = {
    # other aliases...
  }
  // lib.optionalAttrs osConfig.programs.aldur.claude-code.enable {
    claude-yolo = "claude --dangerously-skip-permissions";
  }
  //
    lib.optionalAttrs (osConfig.programs.aldur.lazyvim.enable || config.programs.aldur.lazyvim.enable)
      {
        lv = "lazyvim";
      };
}
