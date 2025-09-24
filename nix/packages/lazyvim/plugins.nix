{ pkgs }:
(with pkgs.vimPlugins; {
  general = [
    lazy-nvim
    LazyVim
    nvim-lspconfig
    bufferline-nvim
    lazydev-nvim
    conform-nvim
    flash-nvim
    friendly-snippets
    gitsigns-nvim
    grug-far-nvim
    noice-nvim
    lualine-nvim
    nui-nvim
    nvim-lint
    nvim-ts-autotag
    ts-comments-nvim
    blink-cmp
    nvim-web-devicons
    persistence-nvim
    plenary-nvim
    telescope-fzf-native-nvim
    telescope-nvim
    todo-comments-nvim
    tokyonight-nvim
    trouble-nvim
    vim-illuminate
    vim-startuptime
    which-key-nvim
    snacks-nvim
    nvim-treesitter-textobjects
    nvim-treesitter.withAllGrammars
    dial-nvim

    fugitive
    vim-rhubarb

    # rust
    (rustaceanvim.overrideAttrs (oa: {
      # TODO: FIXME: https://github.com/nvim-neotest/neotest/issues/530
      doCheck = false;
    }))
    crates-nvim

    SchemaStore-nvim

    wiki-vim

    auto-save-nvim

    # markdown
    markdown-preview-nvim
    render-markdown-nvim

    {
      plugin = mini-ai;
      name = "mini.ai";
    }
    {
      plugin = mini-icons;
      name = "mini.icons";
    }
    {
      plugin = mini-pairs;
      name = "mini.pairs";
    }
    {
      plugin = mini-surround;
      name = "mini.surround";
    }
    {
      plugin = catppuccin-nvim;
      name = "catppuccin";
    }

    {
      plugin = (pkgs.vimUtils.buildVimPlugin rec {
        name = "tinymd.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "aldur";
          repo = name;
          rev = "f1caf374827de0e01a7bc90bdb6761fcbfab3b1f";
          hash = "sha256-Sl+L3fQMs/YsVllDuJpmwFNGtaDeta5okH3Kl5+xI1g=";
        };
      });
      name = "tinymd.nvim";
    }

    {
      plugin = (pkgs.symlinkJoin {
        name = "clarity.nvim_treesitter";
        paths = [
          (pkgs.vimUtils.buildVimPlugin {
            name = "clarity.nvim";
            src = pkgs.fetchFromGitHub {
              owner = "aldur";
              repo = "clarity.nvim";
              rev = "8454b987490174d53fcd0942c9634d7ca0ffc443";
              hash = "sha256-s9SoX9ZjiWX4FnPToH0ujp5kUs5/e9Jue7RncUyqCl0=";
            };
            doCheck = false; # Missing runtime dependencies for "require" check
          })
          (pkgs.neovimUtils.grammarToPlugin (pkgs.tree-sitter.buildGrammar rec {
            language = "clarity";
            version = "ef0552d593a64d6d2936090a44f0ad9f5d54a37f";
            src = pkgs.fetchFromGitHub {
              owner = "xlittlerag";
              repo = "tree-sitter-${language}";
              rev = version;
              hash = "sha256-xBNJuT3d6GN+ocbtdJE1XyosMHwDMnRFIrScPr5pzwc=";
            };
          }))
        ];
      });
      name = "clarity.nvim";
    }

    {
      plugin = ((pkgs.vimUtils.buildVimPlugin {
        name = "link.vim";
        src = pkgs.fetchFromGitHub {
          owner = "qadzek";
          repo = "link.vim";
          rev = "0acbf748ae052edf0bd4d70a632a1bb289e1eb33";
          hash = "sha256-1Eq2arCC5dYDLCk5P2y3Gl1vv1TB3lpq56kJZNCQ7sI=";
        };
      }));
      name = "link.vim";
    }

    {
      plugin = (pkgs.vimUtils.buildVimPlugin rec {
        name = "venv-selector.nvim";
        src = pkgs.fetchFromGitHub {
          owner = "linux-cultist";
          repo = name;
          rev = "2b49d1f8b8fcf5cfbd0913136f48f118225cca5d";
          hash = "sha256-mz9RT1foan2DCHTZppuPZHaEqREqOHg2WU7uk3bjl0E=";
        };
      });
      name = "venv-selector.nvim";
    }
  ];
})
