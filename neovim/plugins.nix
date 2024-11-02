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
  fzf-vim
  zen-mode-nvim
  dressing-nvim
  wiki-vim

  # Fix the quickfix
  (vim-qf.overrideAttrs {
    patches = [
      # TODO: Remove me if 131 gets merged.
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
  lsp_signature-nvim
  fidget-nvim
  actions-preview-nvim
  nui-nvim
  efmls-configs-nvim

  # Snippets
  ultisnips
  vim-snippets

  # Completion
  nvim-cmp
  cmp-nvim-lsp
  cmp-buffer
  cmp-path
  cmp-nvim-lua
  cmp-cmdline
  cmp-nvim-tags
  cmp-beancount
  cmp-nvim-ultisnips
]
++ (with pkgs; [
  (vimUtils.buildVimPlugin {
    name = "ltex_extra-nvim";
    src = fetchFromGitHub {
      owner = "barreiroleo";
      repo = "ltex_extra.nvim";
      rev = "57192d7ae5ba8cef3c10e90f2cd62d4a7cdaab69"; # dev branch
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
    name = "gen.nvim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = name;
      rev = "fa8e149c6ead647244c9ee86eb17dfcf48284ffb";
      hash = "sha256-ZHFyXkhTv236NEFbTsCv+6/L9xED34B6YC4AKwq9Kf0=";
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
