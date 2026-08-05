{
  pkgs,
  pkgsUnstable,
  # Rev-pinned plugins, see ./plugins.
  pinnedPlugins,
}:
let
  ts = pkgs.vimPlugins.nvim-treesitter;
  grammar = name: pkgs.neovimUtils.grammarToPlugin ts.builtGrammars.${name};

  # Minimal set of grammars for the -light version.
  curatedGrammars = [
    "bash"
    "c"
    "diff"
    "fish"
    "json"
    "lua"
    "luadoc"
    "luap"
    "markdown"
    "markdown_inline"
    "nix"
    "printf"
    "python"
    "query"
    "regex"
    "toml"
    "vim"
    "vimdoc"
    "xml"
    "yaml"
  ];
in
with pkgs.vimPlugins;
{
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
    dial-nvim

    nvim-treesitter-textobjects
    # The core plugin only; grammars are per-category plugins below, which
    # init.lua discovers from the runtimepath (see its get_installed patch).
    nvim-treesitter

    vim-fugitive
    vim-rhubarb

    wiki-vim

    auto-save-nvim

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
      plugin = pinnedPlugins.tinymd-nvim;
      name = "tinymd.nvim";
    }

    {
      # The plugin ships only the queries, so pair it with the parser.
      plugin = pkgs.symlinkJoin {
        name = "clarity.nvim_treesitter";
        paths = [
          pinnedPlugins.clarity-nvim
          (pkgs.neovimUtils.grammarToPlugin pinnedPlugins.tree-sitter-clarity)
        ];
      };
      name = "clarity.nvim";
    }

    {
      plugin = pinnedPlugins.link-vim;
      name = "link.vim";
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
                src = pkgs.fetchurl {
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
              # Neovim's 'encoding' is hardwired to utf-8, so it only ever
              # loads {lang}.utf-8.{spl,sug}; latin1 variants are dead weight.
              builtins.mapAttrs getSpell {
                "it.utf-8.spl" = "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
                "it.utf-8.sug" = "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
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
  ]
  ++ map grammar curatedGrammars;

  # Categories
  # NOTE: add new ones to `allCategories` in `./lazyvim.nix`.
  treesitterAll = map pkgs.neovimUtils.grammarToPlugin ts.allGrammars;
  markdown = [
    (markdown-preview-nvim.overrideAttrs (old: {
      runtimeDeps = [ pkgs.nodejs-slim-runtime ];
      postInstall = (old.postInstall or "") + ''
        chmod -R u+w $out/app/node_modules
        node ${../../overlays/prune-node-modules.js} $out/app
        find $out/app/node_modules -xtype l -delete
      '';
    }))
    render-markdown-nvim
  ];
  python = [
    {
      # nixpkgs' stable channel trails the rev this was pinned to, so take it
      # from unstable, where it currently matches exactly.
      plugin = pkgsUnstable.vimPlugins.venv-selector-nvim;
      name = "venv-selector.nvim";
    }
  ];
  json = [ SchemaStore-nvim ];
  rust = [
    rustaceanvim
    crates-nvim
  ];
  beancount = [ (grammar "beancount") ];
}
