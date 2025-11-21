{
  pkgs,
  inputs,
  stateVersion,
  lib,
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
    packages = [ pkgs.gpg-encrypt ];

    file."Documents/Notes/.marksman.toml".text = "";
  };

  programs = {
    clipshare.enable = true;

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

    difftastic = {
      # enabled by default for `git diff`
      # enabled with `--ext-diff` to git show and git log -p
      enable = true;

      git.enable = true;
      git.diffToolMode = false;
    };

    git = {
      enable = true;

      settings = {
        user = {
          name = "aldur";
          email = "aldur@users.noreply.github.com";
        };

        commit.verbose = true;
        push = {
          default = "current";
          autoSetupRemote = true;
          followTags = true;
        };

        pull.default = "current";
        pull.rebase = true;

        rebase.autoStash = true;

        rerere.enabled = true;
        rerere.autoUpdate = true;

        # https://blog.gitbutler.com/git-tips-2-new-stuff-in-git/
        column.ui = "auto";
        branch.sort = "-committerdate";

        # https://jvns.ca/blog/2024/02/16/popular-git-config-options/
        merge.conflictStyle = "zdiff3";
        diff.algorithm = "histogram";
        transfer.fsckobjects = true;
        fetch.fsckobjects = true;
        receive.fsckObjects = true;

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

    tmux = {
      enable = true;

      extraConfig = ''
        set -g default-terminal "screen-256color"

        # as required by nvim
        set-option -g focus-events on
        # make nvim autoread work
        set-option -a terminal-features ',screen256color:RGB'

        set-option -sg escape-time 10
      '';
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
}
