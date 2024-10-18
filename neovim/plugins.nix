{ pkgs, ... }: with pkgs; [
  vimPlugins.nvim-treesitter.withAllGrammars
  vimPlugins.nvim-treesitter-textobjects
  vimPlugins.nvim-treesitter-context

  vimPlugins.investigate-vim # Smart documentation finder
  vimPlugins.vim-qf # Fix the quickfix
  vimPlugins.pear-tree # Auto-pair
  vimPlugins.vim-lion # gR<symbol> to align text
  vimPlugins.undotree # UndotreeToggle
  vimPlugins.vim-gutentags # Tag management
  vimPlugins.fzf-vim
  vimPlugins.zen-mode-nvim
  vimPlugins.dressing-nvim
  vimPlugins.wiki-vim

  # Tim Pope
  vimPlugins.vim-repeat # '.' for plugin actions
  vimPlugins.vim-surround # all about surrounding
  vimPlugins.vim-scriptease # easier plugin development
  vimPlugins.vim-unimpaired #complementary mappings
  vimPlugins.vim-dispatch # async job execution
  vimPlugins.vim-speeddating # C-a / C-x for dates

  # - :%Subvert/facilit{y,ies}/building{,s}/g
  # - fooBar -> `crs` -> foo_bar
  vimPlugins.vim-abolish

  # Git integration
  vimPlugins.vim-fugitive # git wrapper
  vimPlugins.vim-rhubarb # GBrowse for GitHub

  # UI
  vimPlugins.lightline-vim # statusbar
  vimPlugins.sonokai # based on Monokai pro

  # language specific
  vimPlugins.vim-python-pep8-indent
  vimPlugins.vimtex
  vimPlugins.vim-go
  vimPlugins.swift-vim
  vimPlugins.vim-fish
  vimPlugins.kotlin-vim
  vimPlugins.nginx-vim
  vimPlugins.rust-vim
  vimPlugins.vim-solidity
  vimPlugins.vim-terraform
  vimPlugins.vim-caddyfile
  vimPlugins.vim-nix

  # TODO: Manually load it
  # vimPlugins.vim-jukit

  # LSP
  vimPlugins.nvim-lspconfig
  vimPlugins.lsp_signature-nvim
  vimPlugins.fidget-nvim
  vimPlugins.actions-preview-nvim
  vimPlugins.nui-nvim

  # Snippets
  vimPlugins.ultisnips
  vimPlugins.vim-snippets

  # Completion
  vimPlugins.nvim-cmp
  vimPlugins.cmp-nvim-lsp
  vimPlugins.cmp-buffer
  vimPlugins.cmp-path
  vimPlugins.cmp-nvim-lua
  vimPlugins.cmp-cmdline
  vimPlugins.cmp-nvim-tags
  vimPlugins.cmp-beancount
  vimPlugins.cmp-nvim-ultisnips
] ++ (with pkgs;
[
  (vimUtils.buildVimPlugin {
    name = "ltex_extra-nvim";
    src = fetchFromGitHub {
      owner = "barreiroleo";
      repo = "ltex_extra.nvim";
      rev = "57192d7ae5ba8cef3c10e90f2cd62d4a7cdaab69";
      hash = "sha256-sjYCAJkDSX+TPEtdMNgFXqcgv43/7Q48haanP5QycT0=";
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
  (vimUtils.buildVimPlugin rec {
    name = "gen.nvim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "7ebb4f1";
      hash = "sha256-jYUJO5vdoWHrxeZN30H5+zvWTePgmEnHig52fnVXrg8=";
    };
  })
  (vimUtils.buildVimPlugin rec {
    name = "notational-fzf-vim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "07f39d9f9dcabaead436001e8b9a1535d996a6d9";
      hash = "sha256-NStUBDmaVM6zieBvVRXbVxCVrIstgAIyqkbj2oYAwGo=";
    };
  })
  (vimUtils.buildVimPlugin rec {
    name = "tinymd.nvim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "1034238f75427076fa1a2745f8b83fa3cee6c623";
      hash = "sha256-C0NEGvTkVO8UGFgCxYMDJf8gtiObkMoldkFXq1PVCW0=";
    };
  })
  (vimUtils.buildVimPlugin rec {
    name = "vim-algorand-teal";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "436308c2724f6389e6347543d7e0699cdf202a3e";
      hash = "sha256-VzTd29lks0ofpgRRcxv8OlnU2O9t/TPvoR0LtteEFVs=";
    };
  })
  (
    pkgs.symlinkJoin {
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
        (pkgs.neovimUtils.grammarToPlugin (pkgs.tree-sitter.buildGrammar rec {
          language = "clarity";
          version = "ca24ba8e2866c025293f8b07c66df332fdd15d5e";
          src = fetchFromGitHub {
            owner = "xlittlerag";
            repo = "tree-sitter-${language}";
            rev = version;
            hash = "sha256-EHFxtOtJyAo/cyjpD9MVmxOGAjDbWx8CbHUww64NKE4=";
          };
        }))
      ];
    }
  )
])
