# measure size with:
# `nix-store -qR (nix build --no-link --print-out-paths .#lazyvim-light)| xargs du -hd0 | sort -rh | head`
{ pkgs }:
(with pkgs; {
  # The survival kit: what every variant needs to start up and edit text.
  # Language servers, formatters and their toolchains live in categories, so
  # `lazyvim-light` stays actually light (see `allCategories` in ./lazyvim.nix).
  general =
    lib.optionals pkgs.stdenv.isLinux [
      # Fixes the following:
      # `libuv-watchdirs has known performance issues. Consider installing inotify-tools.`
      inotify-tools
    ]
    ++ [
      curl
      fd
      gitMinimal
      lazygit
      ripgrep
      shfmt
      stylua
    ];

  # Categories
  # NOTE: add new ones to `allCategories` in `./lazyvim.nix`.

  # Workstation comforts that no single language claims.
  ide = [
    ast-grep
    harper
    lua-language-server
    prettierd
  ];

  rust = [ rust-analyzer ];
  go = [ gopls ];
  typescript = [ (vtsls.override { nodejs-slim_22 = nodejs-slim; }) ];
  solidity = [
    (pkgs.callPackage
      ../nomicfoundation-solidity-language-server/nomicfoundation-solidity-language-server.nix
      { }
    )
  ];
  nix = [
    nil
    nixfmt
    statix
  ];
  python = [
    basedpyright
    ruff
  ];
  markdown = [
    markdownlint-cli2
    marksman
    nodejs-slim # required by markdown-preview
    pandoc
    (pkgs.callPackage ../pandoc_md2html_assets/md2html.nix { })
  ];
  json = [ vscode-langservers-extracted ];
  toml = [ taplo ];
  # Only the editor side; bean-check/bean-format come from the surrounding
  # ledger environment, so diagnostics run against *its* beancount rather
  # than a second copy's.
  beancount = [ beancount-language-server ];
})
