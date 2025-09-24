# measure size with:
# `nix-store -qR (nix build --no-link --print-out-paths .#lazyvim-light)| xargs du -hd0 | sort -rh | head`
{ pkgs }:
(with pkgs; {
  general = lib.optionals pkgs.stdenv.isLinux [
    # Fixes the following:
    # ⚠️ WARNING libuv-watchdirs has known performance issues. 
    # Consider installing inotify-tools.
    inotify-tools
  ] ++ [

    ast-grep
    basedpyright
    beancount # bean-format
    beancount-language-server
    curl
    fd
    git
    harper
    lua-language-server
    marksman
    markdownlint-cli2
    nil
    nixfmt-classic
    prettierd
    ripgrep
    ruff
    shfmt
    stylua
    taplo
    vscode-langservers-extracted

    pandoc

    (pkgs.callPackage ../pandoc_md2html_assets/md2html.nix { })
  ]
  ++ [
    # NOTE: lazygit can't create its own config file, so we add one from `nix`.
    (pkgs.writeShellScriptBin "lazygit" ''
      exec ${pkgs.lazygit}/bin/lazygit --use-config-file ${pkgs.writeText "lazygit_config.yml" ""} "$@"
    '')
  ];

  # Categories
  # NOTE: add new ones to `allCategories` in `./lazyvim.nix`.
  rust = [
    cargo
    rust-analyzer
    stdenv.cc.cc
  ];
  go = [
    go
    gopls
  ];
  typescript = [
    vtsls
    typescript-language-server
  ];
  solidity = [
    (pkgs.callPackage
      ../nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { }
    )
  ];
})
