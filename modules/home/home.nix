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

  customTools = with pkgs; [
    claude-log
    flake-lock-cooldown
    flatten-pdf
    fps
    gpg-encrypt
    (lazyvim-popup.override (lib.optionalAttrs (lazyvim-bin != null) { inherit lazyvim-bin; }))
    lstrip
    shrink-pdf
    split-pdf
    tmux-palette
    totp-qr-decode
    watermark-pdf
  ];

  aldurs-tools = pkgs.callPackage ../../packages/aldurs-tools { tools = customTools; };

  # Absolute path to the `lazyvim` binary, or null when no variant of it is
  # part of this configuration. The nixCats modules expose their built package
  # under `out.packages` (only populated while enabled); the sandboxed
  # `jailed-lazyvim` alternative ships the same binary via `home.packages`.
  lazyvim-bin =
    let
      fromModule = cfg: lib.attrByPath [ "out" "packages" "lazyvim" ] null cfg;
      package =
        if osConfig.programs.aldur.lazyvim.enable then
          fromModule osConfig.programs.aldur.lazyvim
        else if config.programs.aldur.lazyvim.enable then
          fromModule config.programs.aldur.lazyvim
        else
          lib.findFirst (p: lib.getName p == "lazyvim") null config.home.packages;
    in
    if package == null then null else lib.getExe' package "lazyvim";
in
{
  imports = [
    inputs.clipshare.homeManagerModules.default
    ./claude-code.nix
    ./dash.nix
    ./w3m.nix
    ./direnv.nix
    ./manpager.nix
    ./llm.nix
    ./nix_search.nix
    ./secrets.nix
    ./qemu-vm.nix
  ];

  home = {
    inherit stateVersion;

    username = "aldur";
    packages = customTools ++ [
      aldurs-tools
      pkgs.moreutils
    ];

    file."Documents/Notes/.marksman.toml".text = "";

    # Keep a stable SSH_AUTH_SOCK across reconnects: each new sshd session
    # rewrites this symlink to the current forwarded socket, so existing
    # shells/tmux panes silently pick up the fresh socket without `fixssh`.
    file.".ssh/rc" = {
      executable = true;
      text = ''
        #!/bin/sh
        if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/auth_sock" ]; then
            ln -sf -- "$SSH_AUTH_SOCK" "$HOME/.ssh/auth_sock"
        fi
      '';
    };
  };

  programs = {
    clipshare.enable = true;

    fish = {
      enable = true;

      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        set -g fish_key_bindings fish_hybrid_key_bindings

        # Inside an SSH session, point at the stable symlink that ~/.ssh/rc
        # keeps fresh. Falls through to whatever SSH_AUTH_SOCK was set to
        # (e.g. local yubikey-agent) if the symlink isn't a live socket.
        if set -q SSH_CONNECTION; and test -S "$HOME/.ssh/auth_sock"
            set -gx SSH_AUTH_SOCK "$HOME/.ssh/auth_sock"
        end

        # gw completions
        complete -c gw -l no-fetch -d "Skip fetching from origin"
        complete -c gw -f -a "(git branch -r --format='%(refname:short)' 2>/dev/null)"
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

        gw = {
          description = "Create or switch to a git worktree for a (new) branch";
          body = ''
            argparse 'h/help' 'no-fetch' -- $argv
            or return 1

            if set -q _flag_help
                echo "Usage: gw [--no-fetch] <branch> [base-ref]"
                return 0
            end

            if test (count $argv) -eq 0
                echo "Usage: gw [--no-fetch] <branch> [base-ref]"
                return 1
            end

            set -l branch $argv[1]

            # Tab-completion offers remote-tracking branches (origin/foo). Strip
            # the remote prefix so we create/switch a LOCAL branch `foo` that
            # tracks the remote, not a local branch literally named `origin/foo`.
            for remote in (git remote)
                if string match -q -- "$remote/*" $branch
                    set branch (string replace -- "$remote/" "" $branch)
                    break
                end
            end

            set -l base
            if test (count $argv) -ge 2
                set base $argv[2]
            else
                set base (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||')
            end

            set -l root (git rev-parse --show-toplevel) || return 1
            set -l path "$root/../"(basename "$root")"-worktrees/"(string replace -a / - $branch)

            if not set -q _flag_no_fetch
                if not git fetch origin 2>/dev/null
                    echo "gw: warning: fetch failed, continuing with local state" >&2
                end
            end

            if test -d "$path"
                cd $path
                return
            end

            # Already checked out elsewhere? Exact-match the branch ref in
            # porcelain output with awk (no regex, so dots or other metachars in
            # branch names can't cause false matches).
            set -l existing_wt (git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree / { wt = substr($0, 10) } $0 == "branch " b { print wt; exit }')
            if test -n "$existing_wt"
                echo "gw: branch '$branch' already checked out at $existing_wt" >&2
                cd $existing_wt
                return
            end

            if git show-ref --verify --quiet "refs/heads/$branch"
                # Local branch exists.
                git worktree add $path $branch
            else if git show-ref --verify --quiet "refs/remotes/origin/$branch"
                # Remote branch exists: new local branch tracking it.
                git worktree add -b $branch $path "origin/$branch"
            else
                # Brand-new branch off the base ref.
                if test -z "$base"
                    echo "gw: no base ref (origin/HEAD unset?); pass one explicitly: gw $branch <base-ref>" >&2
                    return 1
                end
                git worktree add -b $branch $path "origin/$base"
            end

            cd $path
          '';
        };

        tcopy = {
          description = "Copy stdin to system clipboard via OSC 52 escape sequence";
          body = ''
            read -z data
            # `base64 | tr -d '\n'` not `base64 -w 0`: -w is GNU-only and
            # macOS /usr/bin/base64 rejects it. tr gives single-line output
            # on both.
            printf "\033]52;c;%s\007" (printf "%s" $data | base64 | tr -d '\n')
          '';
        };

        gbrowse = {
          description = "Print browse URLs for the current branch on each remote";
          body = ''
            set branch (git branch --show-current)
            set remotes (git remote)

            if test -z "$remotes"
                echo "No remotes found"
                return 1
            end

            # Strip remote prefix if branch starts with a known remote name
            for remote in $remotes
                if echo "$branch" | grep -q "^$remote/"
                    set branch (echo "$branch" | sed "s/^$remote\///")
                    break
                end
            end

            for remote in $remotes
                set remote_url (git remote get-url $remote 2>/dev/null)
                set url (echo "$remote_url" \
                    | sed 's/^ssh:\/\/[^@]*@/https:\/\//' \
                    | sed 's/^[^@]*@\([^:]*\):/https:\/\/\1\//' \
                    | sed 's/\.git$//')

                set branch_path "tree"
                if echo "$remote_url" | grep -qi "forgejo"
                    set branch_path "src/branch"
                end

                set full_url "$url/$branch_path/$branch"
                printf "%s\t\033]8;;%s\033\134%s\033]8;;\033\134\n" "$remote" "$full_url" "$full_url"
            end
          '';
        };

        tmux-move-windows = {
          description = "Move all windows from one tmux session into another";
          body = ''
            if test (count $argv) -ne 2
                echo "Usage: tmux-move-windows <source-session> <target-session>"
                return 1
            end

            set -l src $argv[1]
            set -l dst $argv[2]

            # Trailing colon on -t ensures tmux interprets it as a session
            # and auto-assigns the window index (avoids index collisions).
            tmux list-windows -t "$src" -F '#I' | while read win
                tmux move-window -s "$src:$win" -t "$dst:"
            end
          '';
        };

        ssh-forward = {
          description = "Start local SSH port forwarding to a remote host";
          body = ''
            if test (count $argv) -lt 2
                echo "Usage: ssh-forward <host> <port> [<port>...]"
                echo "       Each <port> is either <remote_port> or <local_port>:<remote_port>"
                return 1
            end

            set -l host $argv[1]
            set -l forwards
            for port in $argv[2..-1]
                if string match -qr : -- $port
                    set -l parts (string split -m 1 : -- $port)
                    set -a forwards -L "$parts[1]:localhost:$parts[2]"
                else
                    set -a forwards -L "$port:localhost:$port"
                end
            end

            ssh -N $forwards "$host"
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
        disableStartupPopups = true;

        git = {
          autoFetch = false;
        };
        gui = {
          skipAmendWarning = true;
          nerdFontsVersion = "3";
        };
      }
      //
        # `e` should open our wrapped nvim, when this configuration has it.
        # These mirror lazygit's built-in "nvim" editPreset with the binary
        # swapped; lazygit quotes {{filename}} itself, and editInTerminal
        # suspends lazygit while nvim runs.
        lib.optionalAttrs (lazyvim-bin != null) {
          os = {
            edit = "${lazyvim-bin} -- {{filename}}";
            editAtLine = "${lazyvim-bin} +{{line}} -- {{filename}}";
            editAtLineAndWait = "${lazyvim-bin} +{{line}} -- {{filename}}";
            openDirInEditor = "${lazyvim-bin} -- {{dir}}";
            editInTerminal = true;
          };
        };
    };

    difftastic = {
      enable = true;
      git.enable = false;
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

        # difftastic as difftool only (not diff.external, which breaks fugitive)
        diff.tool = "difftastic";
        difftool.difftastic.cmd = ''difft "$MERGED" "$LOCAL" "abcdef1" "100644" "$REMOTE" "abcdef2" "100644"'';
        pager.difftool = true;
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

    tmux = (import ../shared/programs/tmux.nix { inherit lib; }) // {
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

  # atuin's daemon (as of 18.10) bind()s its unix socket without unlink()-ing
  # a stale one first, so launchd's KeepAlive crash-loops with EADDRINUSE
  # after any unclean shutdown. Strip the leftover socket before exec.
  launchd.agents = lib.mkIf pkgs.stdenv.isDarwin {
    atuin-daemon.config.ProgramArguments = lib.mkForce [
      "/bin/sh"
      "-c"
      "rm -f ${config.programs.atuin.settings.daemon.socket_path} && exec ${lib.getExe config.programs.atuin.package} daemon"
    ];
  };

  # NOTE: Pinentry configured by each respective module
  services.gpg-agent.enable = true;

  home.shellAliases = {
    gd = "git -c diff.external=difft diff";
    gdl = "git -c diff.external=difft log -p --ext-diff";
    gds = "git -c diff.external=difft show --ext-diff";
  }
  //
    # `lv` shortcut whenever a `lazyvim` command is on PATH: either the nixCats
    # module (`aldur.lazyvim.enable`) or a sandboxed `jailed-lazyvim` wrapper
    # added to `home.packages`, which ships the same `lazyvim` binary.
    lib.optionalAttrs
      (
        osConfig.programs.aldur.lazyvim.enable
        || config.programs.aldur.lazyvim.enable
        || lib.any (p: lib.getName p == "lazyvim") config.home.packages
      )
      {
        lv = "lazyvim";
      };
}
