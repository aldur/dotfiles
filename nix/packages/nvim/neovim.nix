# https://ayats.org/blog/neovim-wrapper
{ pkgs, lib, nvim-package ? pkgs.neovim-unwrapped, }:
let
  packageName = "aldur.nvim";

  devTools = with pkgs;
    [
      # Core tools
      # mermaid-filter
      atuin
      bashInteractive
      bat
      coreutils
      curl
      delta
      diffutils
      direnv
      fd
      fzf
      git
      git-crypt
      jq
      less
      nix-direnv
      openssh # required to sign commits
      pandoc
      perl
      ripgrep
      universal-ctags
      which

      (python3.withPackages (ps: with ps; [ beancount ]))

      # --- LSPs ---

      # Broken due to https://github.com/neomutt/lsp-tree-sitter/issues/4
      # autotools-language-server

      astyle
      basedpyright
      beancount
      beancount-language-server
      bibtool
      cargo
      ccls
      clippy
      deno
      dockerfile-language-server
      dotenv-linter
      efm-langserver
      fish # to lint fish files
      fish-lsp
      hadolint
      harper
      html-tidy
      jinja-lsp
      libxml2
      ltex-ls
      lua-language-server
      luaformatter
      luarocks
      marksman
      mdl
      nil
      nix
      nixd
      nixfmt-rfc-style
      nodejs
      pgformatter
      poetry
      ripgrep
      ruff
      rust-analyzer
      rustc
      rustfmt
      shellcheck
      shfmt
      solc
      sqlint
      superhtml
      (opentofu.overrideAttrs (old: {
        postInstall = old.postInstall + ''
          ln -s $out/bin/tofu $out/bin/terraform
        '';
      }))
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

      nodePackages.prettier
      nodePackages.sql-formatter
      # nodePackages.prettier-plugin-solidity
      nodePackages.typescript-language-server

      # (iwe.override (
      #   let
      #     rp = pkgs.rustPlatform;
      #   in
      #   {
      #     rustPlatform = rp // {
      #       buildRustPackage =
      #         args:
      #         rp.buildRustPackage (
      #           args
      #           // rec {
      #             version = "0.0.27";
      #             src = fetchFromGitHub {
      #               owner = "iwe-org";
      #               repo = "iwe";
      #               tag = "iwe-v${version}";
      #               hash = "sha256-4qKZnJa7rBMReWJO7iutp9SOKKL5BrxbZQySdogD03s=";
      #             };
      #             cargoHash = "sha256-pakgzQ268WNjIM0ykKm9s3x0uCj4Z+H3/c9+2hWjx10=";
      #           }
      #         );
      #     };
      #   }
      # ))
    ] ++ [
      (import ../solhint/default.nix { inherit pkgs; }).solhint

      (pkgs.callPackage ../sol/sol.nix { }).sol
      (pkgs.callPackage ../clarinet/clarinet.nix { }).clarinet

      # TODO
      # (import
      #   ../mermaid-filter/default.nix
      #   { inherit pkgs; }).mermaid-filter
    ];

  plugins = (import ./plugins.nix) pkgs;

  foldPlugins = builtins.foldl'
    (acc: next: acc ++ [ next ] ++ (foldPlugins (next.dependencies or [ ])))
    [ ];

  pluginsWithDeps = lib.unique (foldPlugins plugins);

  getSpell = name: spellHash:
    pkgs.stdenv.mkDerivation {
      pname = "${name}";
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

  binToPath = prefix: name:
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

  additionallyInPath = (lib.optionals pkgs.stdenv.isDarwin
    (let usrBinToPath = binToPath "/usr/bin";
    in [
      (usrBinToPath "open")
      (usrBinToPath "pbpaste")
      (usrBinToPath "pbcopy")
      (usrBinToPath "man")
      (usrBinToPath "cc")
      (usrBinToPath "strip")
      (usrBinToPath "trash")
    ]))
    ++ (lib.optionals (pkgs.stdenv.isLinux && builtins.pathExists "/etc/NIXOS")
      (let currentSystemToPath = binToPath "/run/current-system/sw/bin";
      in [
        # NOTE: We need to ensure this is in path
        (currentSystemToPath "man")
      ]));

  spells = builtins.attrValues
    (builtins.mapAttrs (name: spellHash: (getSpell name spellHash)) {
      "it.latin1.spl" =
        "sha256:05sxffxdasmszd9r2xzw5w70jd41qs1kb02b122m9cccgbhkf8dz";
      "it.latin1.sug" =
        "sha256:1b4swv4khh7s4lp1w6dq6arjhni3649cxbm0pmfrcy0q1i0yyfmx";
      "it.utf-8.spl" =
        "sha256:04vlmri8fsza38w7pvkslyi3qrlzyb1c3f0a1iwm6vc37s8361yq";
      "it.utf-8.sug" =
        "sha256:0jnf4hkpr4hjwpc8yl9l5dddah6qs3sg9ym8fmmr4w4jlxhigfz0";
      "es.latin1.spl" =
        "sha256:0h8lhir0yk2zcs8rjn2xdsj2y533kdz7aramsnv0syaw1y82mhq7";
      "es.latin1.sug" =
        "sha256:0jryzc3l1n4yfrf43cx188h0xmk5qfpzc4dqnxn627dx57gn799b";
      "es.utf-8.spl" =
        "sha256:1qvv6sp4d25p1542vk0xf6argimlss9c7yh7y8dsby2wjan3fdln";
      "es.utf-8.sug" =
        "sha256:0v5x05438r8aym2lclvndmjbshsfzzxjhqq80pljlg35m9w383z7";
    });

  packpath = pkgs.runCommandLocal "packpath" { } ''
    mkdir -p $out/pack/${packageName}/{start,opt}

    ln -vsfT ${./aldur.nvim} $out/pack/${packageName}/start/aldur.nvim

    ${lib.concatMapStringsSep "\n" (plugin:
      "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}")
    pluginsWithDeps}
  '';

  spellpath = pkgs.runCommandLocal "spellpath" { } ''
    mkdir -p $out/spell

    ${lib.concatMapStringsSep "\n" (spell:
      let spellName = lib.getName spell;
      in "ln -vsfT ${spell}/${spellName} $out/spell/${spellName}") spells}
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
in pkgs.symlinkJoin {
  name = "nvim";
  paths = [ nvim-package ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim \
      --set PATH ${
        lib.makeBinPath (devTools ++ [ "$out" ] ++ additionallyInPath)
      } \
      --set DIRENVSHELL ${shell}/bin/fish \
      --set DIRENV_LOG_FORMAT "direnv: %s" \
      --add-flags '-u' \
      --add-flags '${./init.vim}' \
      --add-flags '--cmd' \
      --add-flags "'set packpath^=${packpath} | set runtimepath^=${spellpath}'" \
      --set-default NVIM_APPNAME nvim-aldur
  '';

  passthru = { inherit packpath; };
}
