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
    rustaceanvim
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

    rec {
      plugin = pkgs.vimUtils.buildVimPlugin {
        inherit name;
        src = pkgs.fetchFromGitHub {
          owner = "aldur";
          repo = name;
          rev = "f1caf374827de0e01a7bc90bdb6761fcbfab3b1f";
          hash = "sha256-Sl+L3fQMs/YsVllDuJpmwFNGtaDeta5okH3Kl5+xI1g=";
        };
      };
      name = "tinymd.nvim";
    }

    {
      plugin = pkgs.symlinkJoin {
        name = "clarity.nvim_treesitter";
        paths = [
          (pkgs.vimUtils.buildVimPlugin {
            name = "clarity.nvim";
            src = pkgs.fetchFromGitHub {
              owner = "aldur";
              repo = "clarity.nvim";
              rev = "be621c9902ab7d897577ba17d74dcb9fa1ee66bc";
              hash = "sha256-6yzQk67VTpjUY33PA8DBLKDc+lDn/Z7gp4jH3AELass=";
            };
            doCheck = false; # Missing runtime dependencies for "require" check
          })
          (pkgs.neovimUtils.grammarToPlugin (
            pkgs.tree-sitter.buildGrammar rec {
              language = "clarity";
              version = "cbb3ffe8688aca558286fd45ed46857a1f3207bb";
              src = pkgs.fetchFromGitHub {
                owner = "xlittlerag";
                repo = "tree-sitter-${language}";
                rev = version;
                hash = "sha256-iylkAIBEpMPzRYHXyFQKMIEZJbqij/8tLdq9z/UPgN8=";
              };
            }
          ))
        ];
      };
      name = "clarity.nvim";
    }

    rec {
      plugin = pkgs.vimUtils.buildVimPlugin {
        inherit name;
        src = pkgs.fetchFromGitHub {
          owner = "qadzek";
          repo = name;
          rev = "0acbf748ae052edf0bd4d70a632a1bb289e1eb33";
          hash = "sha256-1Eq2arCC5dYDLCk5P2y3Gl1vv1TB3lpq56kJZNCQ7sI=";
        };
      };
      name = "link.vim";
    }

    rec {
      plugin = pkgs.vimUtils.buildVimPlugin {
        inherit name;
        src = pkgs.fetchFromGitHub {
          owner = "linux-cultist";
          repo = name;
          rev = "2b49d1f8b8fcf5cfbd0913136f48f118225cca5d";
          hash = "sha256-mz9RT1foan2DCHTZppuPZHaEqREqOHg2WU7uk3bjl0E=";
        };
      };
      name = "venv-selector.nvim";
    }

    rec {
      plugin = pkgs.vimUtils.buildVimPlugin {
        inherit name;
        src =
          let
            getSpell =
              name: spellHash:
              pkgs.stdenv.mkDerivation {
                pname = name;
                version = "201901191939";
                src = builtins.fetchurl {
                  url = "https://ftp.nluug.nl/pub/vim/runtime/spell/${name}";
                  sha256 = spellHash;
                };
                phases = [ "installPhase" ];
                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/
                  ln -s $src $out/${name}
                  runHook postInstall
                '';
              };

            spells = builtins.attrValues (
              builtins.mapAttrs getSpell {
                "it.latin1.spl" = "sha256:05sxffxdasmszd9r2xzw5w70jd41qs1kb02b122m9cccgbhkf8dz";
                "it.latin1.sug" = "sha256:1b4swv4khh7s4lp1w6dq6arjhni3649cxbm0pmfrcy0q1i0yyfmx";
                "it.utf-8.spl" = "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
                "it.utf-8.sug" = "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
                "es.latin1.spl" = "sha256:0h8lhir0yk2zcs8rjn2xdsj2y533kdz7aramsnv0syaw1y82mhq7";
                "es.latin1.sug" = "sha256:0jryzc3l1n4yfrf43cx188h0xmk5qfpzc4dqnxn627dx57gn799b";
                "es.utf-8.spl" = "sha256:1qvv6sp4d25p1542vk0xf6argimlss9c7yh7y8dsby2wjan3fdln";
                "es.utf-8.sug" = "sha256:0v5x05438r8aym2lclvndmjbshsfzzxjhqq80pljlg35m9w383z7";
              }
            );
          in
          pkgs.runCommandLocal "spellpath" { } ''
            mkdir -p $out/spell

            ${pkgs.lib.concatMapStringsSep "\n" (
              spell:
              let
                spellName = pkgs.lib.getName spell;
              in
              "ln -vsfT ${spell}/${spellName} $out/spell/${spellName}"
            ) spells}
          '';
      };
      name = "spells";
    }
  ];
})
