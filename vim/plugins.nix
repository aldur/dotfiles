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
  # TODO: Bump this and use vimPlugins packaged
  (vimUtils.buildVimPlugin {
    name = "wiki.vim";
    src = fetchFromGitHub {
      owner = "lervag";
      repo = "wiki.vim";
      rev = "v0.8";
      hash = "sha256-E+hGi7DTsGqGHi7VrcdOxCYQIa5Wy2Fu0yLa3ASiaAA=";
    };
  })
  # TODO: Bump this and use vimPlugins packaged
  # (vimUtils.buildVimPlugin {
  #   name = "fidget.nvim";
  #   src = fetchFromGitHub {
  #     owner = "j-hui";
  #     repo = "fidget.nvim";
  #     rev = "0ba1e16d07627532b6cae915cc992ecac249fb97";
  #     hash = "sha256-rmJgfrEr/PYBq0S7j3tzRZvxi7PMMaAo0k528miXOQc=";
  #   };
  # })
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
    name = "genn.nvim";
    src = fetchFromGitHub {
      owner = "David-Kunz";
      repo = "gen.nvim";
      rev = "83f1d6b6ffa6a6f32f6a93a33adc853f27541a94";
      hash = "sha256-rBUltJdluSseNUiTfjBZyuBwrGrASWbW1ROVdcAW6ug=";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "notational-fzf-vim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = "notational-fzf-vim";
      rev = "07f39d9f9dcabaead436001e8b9a1535d996a6d9";
      hash = "sha256-NStUBDmaVM6zieBvVRXbVxCVrIstgAIyqkbj2oYAwGo=";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "vim-markdown";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = "vim-markdown";
      rev = "9fa61d2f5a1d28bc877e328b13ebdc3cac0d0f0e";
      hash = "sha256-rIO/UuSbdwHjRLbHoUC2ke9BaxQkssmyYc6TlmxgFU8";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "vim-algorand-teal";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = "vim-algorand-teal";
      rev = "436308c2724f6389e6347543d7e0699cdf202a3e";
      hash = "sha256-rIO/UuSbdwHjRLbHoUC2ke9BaxQkssmyYc6TlmxgFU8";
    };
  })
  (vimUtils.buildVimPlugin {
    name = "clarity.nvim";
    src = fetchFromGitHub {
      owner = "aldur";
      repo = "clarity.nvim";
      rev = "86444d23bec2a810311da4cee4028317d67d630c";
      hash = "sha256-rIO/UuSbdwHjRLbHoUC2ke9BaxQkssmyYc6TlmxgFU8";
    };
  })
])
