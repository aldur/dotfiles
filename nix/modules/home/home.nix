{ pkgs, inputs, ... }:
let
  gpgKeys = pkgs.fetchurl {
    url = "https://github.com/aldur.gpg";
    sha256 = "sha256-x1H++Oqax/ZacnsTgurRFWI9I+/E7wb5pj8PXf7fhmw=";
  };
in {
  imports = [ inputs.clipshare.homeManagerModules.default ./w3m.nix ];

  home.username = "aldur";
  home.packages = [ ];

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
      set -g fish_key_bindings fish_hybrid_key_bindings
    '';
    functions = {
      fish_hybrid_key_bindings = {
        description =
          "Vi-style bindings that inherit emacs-style bindings in all modes";
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
    plugins = [{
      name = "z";
      src = pkgs.fishPlugins.z;
    }];
  };

  programs.git = {
    enable = true;
    userName = "aldur";
    userEmail = "aldur@users.noreply.github.com";

    extraConfig = {
      commit.verbose = true;

      push.default = "current";
      push.autoSetupRemote = true;
      push.followTags = true;

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
      gpg.format = "ssh";

      gpg.ssh.defaultKeyCommand = "sh -c 'echo key::$(ssh-add -L | tail -n 1)'";
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  home.stateVersion = "25.05";

  programs.atuin = {
    enable = true;
    daemon.enable = true;
    settings = { enter_accept = false; };
  };

  programs.fzf = { enable = true; };

  programs.tmux = {
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

  programs.gpg = {
    enable = true;
    scdaemonSettings = { pcsc-shared = true; };
    publicKeys = [{
      source = "${gpgKeys}";
      trust = 5;
    }];
  };
}
