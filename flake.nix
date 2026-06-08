{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        darwin.follows = "";
        home-manager.follows = "home-manager";
        systems.follows = "systems";
      };
    };

    nixCats.url = "github:BirdeeHub/nixCats-nvim";
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    clipshare = {
      url = "github:aldur/clipshare";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dashp = {
      url = "github:aldur/dashp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    detnix = {
      url = "github:DeterminateSystems/nix-src";
      inputs = {
        # `detnix` wants its own Rust version
        # nixpkgs.follows = "nixpkgs-unstable";

        nixpkgs-regression.follows = "";
        nixpkgs-23-11.follows = "";
        flake-parts.follows = "";
        git-hooks-nix.follows = "";
      };

    };

    # preservation has no inputs of its own (pure NixOS module).
    preservation.url = "github:nix-community/preservation";
  };
  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      nixpkgs-unstable,
      ...
    }@inputs:
    let
      # This ugly thing ensures that, when descendant flakes (e.g. those in
      # `base_hosts`) use this flake, all (this flake) inputs are correctly
      # passed as arguments to the modules.
      thisFlakeInputs = inputs // {
        inherit self;
      };
    in
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgsArgs = {
          inherit system;
          overlays = import ./overlays { inherit self; };
        };

        pkgs = import nixpkgs pkgsArgs;
        pkgsUnstable = import nixpkgs-unstable pkgsArgs;
        lazyvims = pkgs.callPackage ./packages/lazyvim/lazyvim.nix { inherit inputs pkgsUnstable; };
        qemu-vm = pkgs.callPackage ./packages/qemu-vm/qemu-vm.nix { inherit inputs; };
      in
      {
        packages = {
          inherit (lazyvims) lazyvim lazyvim-light;
          inherit (pkgs)
            beancount-language-server # from aldur/beancount-language-server
            nomicfoundation-solidity-language-server
            shrink-pdf
            solidity-docset
            remarks
            flatten-pdf
            watermark-pdf
            flake-lock-cooldown
            ;
          llm = pkgs.llmWithPlugins;
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          inherit (pkgs) uvc-util c920-defaults;
        };

        # Legacy packages are not automatically flake-checked
        legacyPackages = {
          inherit qemu-vm;
        };

        apps.validate-claude-settings = {
          type = "app";
          program =
            let
              script = pkgs.writeShellApplication {
                name = "validate-claude-settings";
                runtimeInputs = [
                  pkgs.curl
                  pkgs.check-jsonschema
                ];
                text = ''
                  settings="''${1:-$HOME/.claude/settings.json}"
                  if [ ! -f "$settings" ]; then
                    echo "error: $settings does not exist" >&2
                    exit 1
                  fi
                  schema=$(mktemp)
                  trap 'rm -f "$schema"' EXIT
                  curl -sSL --fail \
                    "https://json.schemastore.org/claude-code-settings.json" \
                    -o "$schema"
                  check-jsonschema --schemafile "$schema" "$settings"
                '';
              };
            in
            "${script}/bin/validate-claude-settings";
        };
      }
    ))
    // {
      templates = {
        vm-nogui = {
          path = ./base_hosts/qemu;
          description = "A QEMU VM";
        };
        lxc-nixos = {
          path = ./base_hosts/crostini;
          description = "An lxc-nixos container to run in ChromeOS Crostini";
        };
      };

      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system
      specialArgs.inputs = thisFlakeInputs;

      utils.github-keys = import ./utils/github-keys.nix { };

      lib.programs = {
        git = import ./modules/shared/programs/git.nix;
        tmux = import ./modules/shared/programs/tmux.nix;
      };

      # Build `specialArgs` for a descendant flake (e.g. those in
      # `base_hosts`): merge its own inputs with this flake's, the latter
      # winning so `self` resolves to aldur-dotfiles. Encodes the merge
      # order once so consumers can't get it backwards.
      lib.mkSpecialArgs = hostInputs: {
        inputs = hostInputs // thisFlakeInputs;
      };

      nixosModules = {
        default = ./modules/nixos/configuration.nix;
        audit = ./modules/nixos/audit.nix;
        docker = ./modules/nixos/docker.nix;
        pragmatism = ./modules/nixos/pragmatism.nix;
        default-editor = ./modules/nixos/default_editor.nix;
        cli = ./modules/cli.nix;
        development = ./modules/development.nix;
        environment = ./modules/environment.nix;

        # Meta-modules: each export pulls in the upstream preservation
        # module alongside our config layer. Consumers just import the
        # one entry from `aldur-dotfiles.nixosModules` and get both.
        preservation-system = {
          imports = [
            inputs.preservation.nixosModules.preservation
            ./modules/nixos/preservation-system.nix
          ];
        };
        preservation-user = {
          imports = [
            inputs.preservation.nixosModules.preservation
            ./modules/nixos/preservation-user.nix
          ];
        };
      };

      darwinModules.default = ./modules/darwin/configuration.nix;
    };
}
