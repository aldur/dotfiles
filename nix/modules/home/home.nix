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

      terminal = "tmux-256color";
      prefix = "c-a";
      baseIndex = 1;
      clock24 = true;
      customPaneNavigationAndResize = true;
      # https://neovim.io/doc/user/faq.html#_esc-in-tmux-or-gnu-screen-is-delayed
      escapeTime = 10;
      focusEvents = true; # required by nvim
      historyLimit = 10000;
      secureSocket = true;
      mouse = true;
      keyMode = "vi";
      newSession = true;

      extraConfig = ''
        # enable RGB support and make nvim autoread work
        set -as terminal-features ',*-256color:RGB'

        # enable hyperlinks
        set -as terminal-features ",*:hyperlinks"

        # enable undercurl and strikethrough
        set -as terminal-features ',*:usstyle'
        set -as terminal-features ',*:strikethrough'

        # automatically re-number windows (do not leave gaps)
        set -g renumber-windows on

        # c-a twice sends c-a to the terminal
        bind C-a send-prefix

        # Center the window list
        set -g status-justify centre

        # split with vi keybindings opening to the current pane's path
        bind-key s split-window -v -c "#{pane_current_path}"
        bind-key v split-window -h -c "#{pane_current_path}"

        # v, c-v to select and vertically select
        bind -T copy-mode-vi v send-keys -X begin-selection
        bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
        # escape to exit copy mode
        bind -T copy-mode-vi Escape send-keys -X cancel

        # Jump to previous/next prompt with [ and ]
        bind-key -T copy-mode-vi [ send-keys -X previous-prompt
        bind-key -T copy-mode-vi ] send-keys -X next-prompt

        # --- Theming ---
        set -g @tokyo-night-tmux_transparent 1

        # Stripped down version of https://github.com/janoamaral/tokyo-night-tmux
        # Night theme colors 
        # BG supports transparent mode via @tokyo-night-tmux_transparent
        %hidden BG="#{?#{==:#{@tokyo-night-tmux_transparent},1},default,#1A1B26}"
        %hidden FG="#a9b1d6"
        %hidden BBLACK="#2A2F41"
        %hidden BLUE="#7aa2f7"
        %hidden GREEN="#73daca"
        %hidden BGREEN="#41a6b5"
        %hidden YELLOW="#e0af68"

        # Status bar
        set -g status-left-length 40
        set -g status-right-length 80
        set -g status-style "bg=#{BG}"

        # Highlight & messages
        set -g mode-style "fg=#{BGREEN},bg=#{BBLACK}"
        set -g message-style "bg=#{BLUE},fg=#{BBLACK}"
        set -g message-command-style "fg=#{BLUE},bg=#{BBLACK}"

        # Panes
        set -g pane-border-style "fg=#{BBLACK}"
        set -g pane-active-border-style "fg=#{BLUE}"
        set -g pane-border-status off

        # Popup
        set -g popup-border-style "fg=#{BLUE}"

        # Status left (session)
        set -g status-left "#[fg=#{BBLACK},bg=#{BLUE},bold] #{?client_prefix,󰠠 ,#[dim]󰤂 }#[bold,nodim]#S "

        # Windows
        set -g window-status-current-format "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{GREEN},bg=#{BBLACK}] #{?#{==:#{pane_current_command},ssh},󰣀 , }#[fg=#{FG},bold,nodim]#I-#P #W#{?window_zoomed_flag, ,}#[nobold]#{?window_last_flag, , }"
        set -g window-status-format "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{FG}] #{?#{==:#{pane_current_command},ssh},󰣀 , }#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#I-#P #W#{?window_zoomed_flag, ,}#[nobold,dim]#[fg=#{YELLOW}]#{?window_last_flag, 󰁯  , }"
        set -g window-status-separator ""

        # Status right (date/time)
        set -g status-right "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{FG},bg=#{BBLACK}] %Y-%m-%d ❬ %H:%M "
        # --- /Theming ---
      '';

      plugins = with pkgs; [
        tmuxPlugins.yank
      ];
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
