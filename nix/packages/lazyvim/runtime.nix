# measure size with:
# `nix-store -qR (nix build --no-link --print-out-paths .#lazyvim-light)| xargs du -hd0 | sort -rh | head`
{ pkgs }:
(with pkgs; {
  general =
    lib.optionals pkgs.stdenv.isLinux [
      # Fixes the following:
      # `libuv-watchdirs has known performance issues. Consider installing inotify-tools.`
      inotify-tools
    ]
    ++ [

      ast-grep
      basedpyright
      curl
      fd
      git
      harper
      lua-language-server
      markdownlint-cli2
      marksman
      prettierd
      ripgrep
      ruff
      shfmt
      stylua
      taplo
      vscode-langservers-extracted

      # Required by nvim-treesitter-main
      nodejs
      tree-sitter

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
  nix = [
    nil
    nixfmt-rfc-style
    statix
  ];
  beancount = [
    beancount
    beancount-language-server
  ];
})
