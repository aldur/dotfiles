{ pkgs }:
''
  # Keep executable caches out of agent-writable worktrees. The sandbox has
  # its own XDG_DATA_HOME, so its approvals and caches remain separate.
  direnv_layout_dir() {
    local project_hash
    project_hash=$(printf '%s' "$PWD" | ${pkgs.coreutils}/bin/sha256sum)
    printf '%s/direnv/layouts/%s\n' \
      "''${XDG_DATA_HOME:-$HOME/.local/share}" "''${project_hash%% *}"
  }

  # Run before .envrc, including when entering through a subdirectory.
  # Select likely environment inputs across the repository, including parent
  # flakes and sibling imports, without reading ordinary source files.
  # These are Git pathspecs; direnv still owns hashing and approvals.
  _direnv_require_inputs() {
    local previous=$PWD envrc index
    envrc=$(find_up .envrc) || return 0
    cd "''${envrc%/*}" || return
    if index=$(${pkgs.git}/bin/git -c core.fsmonitor=false rev-parse --git-path index 2>/dev/null); then
      watch_file "$index"
      local -a inputs=()
      local -a patterns=(
        ':(top,glob)**/*.nix'
        ':(top,glob)**/*.sh'
        ':(top,glob)**/flake.lock'
        ':(top,glob)**/.envrc*'
      )
      mapfile -d "" -t inputs < <(${pkgs.git}/bin/git -c core.fsmonitor=false ls-files \
        --cached --recurse-submodules -z -- "''${patterns[@]}") || return
      # Process substitution must not hide a failed Git command.
      wait "$!" || return
      if (( ''${#inputs[@]} )); then
        require_allowed "''${inputs[@]}" || return
      fi
    fi
    cd "$previous"
  }
  _direnv_require_inputs || exit 1
  unset -f _direnv_require_inputs
''
