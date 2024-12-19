{ pkgs, ... }:
with pkgs.vimPlugins;
[
  nvim-treesitter.withAllGrammars
  nvim-treesitter-textobjects
  nvim-treesitter-context

  investigate-vim # Smart documentation finder
  pear-tree # Auto-pair
  vim-lion # gR<symbol> to align text
  undotree # UndotreeToggle
  vim-gutentags # Tag management
  fzf-lua
  zen-mode-nvim
  trouble-nvim
  dressing-nvim

  plenary-nvim # Required by CodeCompanion
  codecompanion-nvim

  nvim-tree-lua
  oil-nvim

  # Fix the quickfix
  (vim-qf.overrideAttrs {
    patches = [
      # TODO: Remove this if 131 gets merged.
      (pkgs.fetchurl {
        url = "https://github.com/romainl/vim-qf/pull/131.patch";
        hash = "sha256-fTdPK+PnuYxef1ha1e1h9uwSCO6NRqRZMkHkXKRtYKc=";
      })
    ];
  })

  # Tim Pope
  vim-repeat # '.' for plugin actions
  vim-surround # all about surrounding
  vim-scriptease # easier plugin development
  vim-unimpaired # complementary mappings
  vim-dispatch # async job execution
  vim-speeddating # C-a / C-x for dates

  # - :%Subvert/facilit{y,ies}/building{,s}/g
  # - fooBar -> `crs` -> foo_bar
  vim-abolish

  # Git integration
  vim-fugitive # git wrapper
  vim-rhubarb # GBrowse for GitHub
  diffview-nvim

  # UI
  lightline-vim # statusbar

  sonokai # based on Monokai pro

  # language specific
  kotlin-vim
  nginx-vim
  rustaceanvim
  swift-vim
  vim-caddyfile
  vim-fish
  vim-go
  vim-nix
  vim-python-pep8-indent
  vim-solidity
  vim-terraform
  vimtex

  # TODO: Manually load it
  # vim-jukit

  # LSP
  nvim-lspconfig
  fidget-nvim
  nui-nvim
  efmls-configs-nvim
  nvim-lightbulb

  # Snippets
  nvim-snippets

  # Completion
  nvim-cmp
  cmp-nvim-lsp
  cmp-buffer
  cmp-async-path
  cmp-nvim-lua
  cmp-cmdline
  cmp-beancount
  cmp-nvim-lsp-signature-help
]
++ (with pkgs; [
  (vimUtils.buildVimPlugin {
    name = "wiki-vim";
    src = fetchFromGitHub {
      owner = "lervag";
      repo = "wiki.vim";
      rev = "197282b271a4b829a3d3645d6fa5bf4180c413fd";
      hash = "sha256-GSGebXjAnKhh9WD0ZPrVWMmbtTdN/Zgr2achGmWjaR8";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "lists.vim";
    src = fetchFromGitHub {
      owner = "lervag";
      repo = "lists.vim";
      rev = "33ced550dc7cc9b9025f2b8b5428bee1d32f355c";
      hash = "sha256-L7x4B6/URT2ocZNZKLmaqLP5RhRWackq0148nUiRq7k=";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "link.vim";
    src = fetchFromGitHub {
      owner = "qadzek";
      repo = "link.vim";
      rev = "8cbc27a10fdef262fc91d40c54c78b36df1c44ce";
      hash = "sha256-EjPfkcgYhxcDCNfAX9lepFzKUFGpG36L1qKKt6peNrk=";
    };
  })
  (vimUtils.buildVimPlugin rec {
    name = "tinymd.nvim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "ea6dda792313fce3fd7f0c95cbce1faccde6e826";
      hash = "sha256-4PzNCmzC0JJNXX9FT81713sKT8QAZaPnlbhaYSp+LsQ=";
    };
  })
  (pkgs.symlinkJoin {
    name = "clarity.nvim_treesitter";
    paths = [
      (vimUtils.buildVimPlugin {
        name = "clarity.nvim";
        src = fetchFromGitHub {
          owner = "aldur";
          repo = "clarity.nvim";
          rev = "86444d23bec2a810311da4cee4028317d67d630c";
          hash = "sha256-rIO/UuSbdwHjRLbHoUC2ke9BaxQkssmyYc6TlmxgFU8=";
        };
      })
      (pkgs.neovimUtils.grammarToPlugin (
        pkgs.tree-sitter.buildGrammar rec {
          language = "clarity";
          version = "ca24ba8e2866c025293f8b07c66df332fdd15d5e";
          src = fetchFromGitHub {
            owner = "xlittlerag";
            repo = "tree-sitter-${language}";
            rev = version;
            hash = "sha256-EHFxtOtJyAo/cyjpD9MVmxOGAjDbWx8CbHUww64NKE4=";
          };
        }
      ))
    ];
  })
])
