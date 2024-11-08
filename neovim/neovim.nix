# https://ayats.org/blog/neovim-wrapper
{ pkgs, lib }:
let
  packageName = "aldur.nvim";

  devTools =
    with pkgs;
    [
      # Core tools
      bashInteractive
      bat
      coreutils
      curl
      diffutils
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

      (python3.withPackages (
        ps: with ps; [
          beancount
        ]
      ))

      # FIXME
      # The following are required to make calls to `neovide`
      # from `neovim` itself work.
      coreutils-prefixed
      gnused

      # --- LSPs ---

      astyle
      autotools-language-server
      beancount
      beancount-language-server
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
      harper
      html-tidy
      libxml2
      ltex-ls
      lua-language-server
      luaformatter
      luarocks
      marksman
      mdl
      nix
      nixd
      nil
      nixfmt-rfc-style
      nodejs
      pgformatter
      pyright
      poetry
      ripgrep
      rust-analyzer
      rustfmt
      rustc
      shfmt
      shellcheck
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
    ]
    ++ [
      (import ../nix/packages/solhint/default.nix { inherit pkgs; }).solhint

      (pkgs.callPackage ../nix/packages/sol/sol.nix { }).sol
      (pkgs.callPackage ../nix/packages/clarinet/clarinet.nix { }).clarinet

      # TODO
      # (import
      #   ../nix/packages/mermaid-filter/default.nix
      #   { inherit pkgs; }).mermaid-filter
    ];

  plugins = (import ./plugins.nix) pkgs;

  foldPlugins = builtins.foldl' (
    acc: next:
    acc
    ++ [
      next
    ]
    ++ (foldPlugins (next.dependencies or [ ]))
  ) [ ];

  pluginsWithDeps = lib.unique (foldPlugins plugins);

  getSpell =
    name: spellHash:
    pkgs.stdenv.mkDerivation {
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

  binToPath =
    prefix: name:
    pkgs.stdenv.mkDerivation {
      name = "${name}";
      src = builtins.toPath "${prefix}/${name}";
      phases = [ "installPhase" ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        ln -s $src $out/bin/${name}
        runHook postInstall
      '';
    };

  additionallyInPath =
    (lib.optionals pkgs.stdenv.isDarwin (
      let
        usrBinToPath = binToPath "/usr/bin";
      in
      [
        (usrBinToPath "open")
        (usrBinToPath "pbpaste")
        (usrBinToPath "pbcopy")
        (usrBinToPath "man")
        (usrBinToPath "cc")
        (usrBinToPath "strip")
      ]
    ))
    ++ (lib.optionals (pkgs.stdenv.isLinux && builtins.pathExists "/etc/NIXOS") (
      let
        currentSystemToPath = binToPath "/run/current-system/sw/bin";
      in
      [
        # NOTE: We need to ensure this is in path
        (currentSystemToPath "man")
      ]
    ));

  spells = builtins.attrValues (
    builtins.mapAttrs (name: spellHash: (getSpell name spellHash)) {
      "it.latin1.spl" = "sha256:05sxffxdasmszd9r2xzw5w70jd41qs1kb02b122m9cccgbhkf8dz";
      "it.latin1.sug" = "sha256:1b4swv4khh7s4lp1w6dq6arjhni3649cxbm0pmfrcy0q1i0yyfmx";
      "it.utf-8.spl" = "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
      "it.utf-8.sug" = "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
    }
  );

  packpath = pkgs.runCommandLocal "packpath" { } ''
    mkdir -p $out/pack/${packageName}/{start,opt}

    ln -vsfT ${./aldur.nvim} $out/pack/${packageName}/start/aldur.nvim

    ${lib.concatMapStringsSep "\n" (
      plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}"
    ) pluginsWithDeps}
  '';

  spellpath = pkgs.runCommandLocal "spellpath" { } ''
    mkdir -p $out/spell

    ${lib.concatMapStringsSep "\n" (
      spell:
      let
        spellName = lib.getName spell;
      in
      "ln -vsfT ${spell}/${spellName} $out/spell/${spellName}"
    ) spells}
  '';

  shell = pkgs.wrapFish {
    localConfig = ''
      # https://esham.io/2023/10/direnv
      export DIRENV_LOG_FORMAT=""
      if ! status is-interactive
            # direnv hook fish | source
            # $(direnv export fish)"
            direnv export fish | source
      else
            echo 'Remember, this is a wrapped version of fish specific for `nvim`.'
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
      --set PATH ${lib.makeBinPath (devTools ++ [ "$out" ] ++ additionallyInPath)} \
      --set DIRENVSHELL ${shell}/bin/fish \
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
