# https://ayats.org/blog/neovim-wrapper
{ pkgs, lib }:
let
  packageName = "aldur.nvim";

  devTools = with pkgs; [
    # Core tools
    bashInteractive
    bat
    coreutils
    curl
    direnv
    fd
    fzf
    git
    git-crypt
    jq
    nix-direnv
    openssh # required to sign commits
    pandoc
    # mermaid-filter
    perl
    ripgrep
    which
    universal-ctags

    (python3.withPackages
      (ps: with ps; [ pynvim beancount ]))

    # --- LSPs ---

    astyle
    beancount
    bibtool
    black
    cargo
    clippy
    deno
    dockerfile-language-server-nodejs
    dotenv-linter
    efm-langserver
    fish # to lint fish files
    hadolint
    html-tidy
    libxml2
    ltex-ls
    lua-language-server
    luaformatter
    luarocks
    marksman
    mdl
    nix
    nil
    nixpkgs-fmt
    nodejs
    pgformatter
    pyright
    ripgrep
    rust-analyzer
    rustfmt
    rustc
    shfmt
    solc
    sqlint
    terraform-ls
    texlab
    tflint
    typescript
    vim-language-server
    vim-vint
    vscode-langservers-extracted
    yaml-language-server
    yamlfix
    yamllint

    luaPackages.luacheck

    python312Packages.cfn-lint
    python312Packages.pyflakes
    python312Packages.python-lsp-server

    nodePackages.prettier
    # nodePackages.prettier-plugin-solidity
    nodePackages.sql-formatter
    nodePackages.typescript-language-server
  ] ++ [
    (import
      ../nix/packages/solhint/default.nix
      { inherit pkgs; }).solhint

    (pkgs.callPackage
      ../nix/packages/sol/sol.nix
      { }).sol

    # TODO
    # (import
    #   ../nix/packages/mermaid-filter/default.nix
    #   { inherit pkgs; }).mermaid-filter
  ];

  plugins = (import ./plugins.nix) pkgs;

  foldPlugins = builtins.foldl'
    (
      acc: next:
        acc
        ++ [
          next
        ]
        ++ (foldPlugins (next.dependencies or [ ]))
    ) [ ];

  pluginsWithDeps = lib.unique (foldPlugins plugins);

  getSpell = name: spellHash: pkgs.stdenv.mkDerivation {
    pname = "${name}";
    version = "201901191939";
    src = builtins.fetchurl {
      url = "http://ftp.vim.org/vim/runtime/spell/${name}";
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

  usrBinInPath = name: pkgs.stdenv.mkDerivation
    {
      name = "${name}";
      src = builtins.toPath "/usr/bin/${name}";
      phases = [ "installPhase" ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        ln -s $src $out/bin/${name}
        runHook postInstall
      '';
    };

  usrBins =
    (lib.optionals pkgs.stdenv.isDarwin [
      (usrBinInPath "open")
      (usrBinInPath "pbpaste")
      (usrBinInPath "pbcopy")
      (usrBinInPath "man")
      (usrBinInPath "cc")
      (usrBinInPath "strip")
    ]);

  spells = builtins.attrValues (builtins.mapAttrs (name: spellHash: (getSpell name spellHash)) {
    "it.latin1.spl" = "sha256:05sxffxdasmszd9r2xzw5w70jd41qs1kb02b122m9cccgbhkf8dz";
    "it.latin1.sug" = "sha256:1b4swv4khh7s4lp1w6dq6arjhni3649cxbm0pmfrcy0q1i0yyfmx";
    "it.utf-8.spl" = "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
    "it.utf-8.sug" = "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
  });

  packpath = pkgs.runCommandLocal "packpath" { } ''
    mkdir -p $out/pack/${packageName}/{start,opt}

    ln -vsfT ${./aldur.nvim} $out/pack/${packageName}/start/aldur.nvim

    ${
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}")
      pluginsWithDeps
    }
  '';

  spellpath = pkgs.runCommandLocal "spellpath" { } ''
    mkdir -p $out/spell

    ${
      lib.concatMapStringsSep
      "\n"
      (
        spell:
        let spellName = lib.getName spell;
        in
        "ln -vsfT ${spell}/${spellName} $out/spell/${spellName}"
      )
      spells
    }
  '';

  shell = pkgs.wrapFish {
    localConfig = ''
      if ! status is-interactive
            eval "$(direnv export fish)"
      else
            echo 'Remember, this is a wrapped version of fish specific for `nvim`.'
            echo 'Evaluating direnv (if any)...'
      end
    '';
  };
in
pkgs.symlinkJoin {
  name = "nvim";
  paths = [ pkgs.neovim-unwrapped ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim \
      --set PATH ${lib.makeBinPath (
          devTools ++ ["$out"] ++ usrBins
        )} \
      --set SHELL ${shell}/bin/fish \
      --add-flags '-u' \
      --add-flags '${./init.vim}' \
      --add-flags '--cmd' \
      --add-flags "'set packpath^=${packpath} | set runtimepath^=${spellpath}'" \
      --set-default NVIM_APPNAME nvim-aldur
  '';

  passthru = {
    inherit packpath;
  };
}
