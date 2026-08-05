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

    # SSH signing keys registered on GitHub, rendered into git's
    # allowed-signers file; refresh with `nix flake update gh-signing-keys`.
    gh-signing-keys = {
      url = "file+https://api.github.com/users/aldur/ssh_signing_keys";
      flake = false;
    };
  };
  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      nixpkgs-darwin,
      nixpkgs-unstable,
      ...
    }@inputs:
    # Not `eachDefaultSystem`: nixpkgs 26.11 dropped x86_64-darwin, so
    # evaluating the unstable-following packages (e.g. `pi`) for it throws.
    # No host here is an Intel Mac; don't export outputs for it.
    (flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgsArgs = {
            inherit system;
            overlays = import ./overlays { inherit self; };
          };

          pkgsBase = if nixpkgs.lib.hasSuffix "-darwin" system then nixpkgs-darwin else nixpkgs;
          pkgs = import pkgsBase pkgsArgs;
          pkgsUnstable = import nixpkgs-unstable pkgsArgs;
          lazyvims = pkgs.callPackage ./packages/lazyvim/lazyvim.nix { inherit inputs pkgsUnstable; };
          qemu-vm = pkgs.callPackage ./packages/qemu-vm/qemu-vm.nix { inherit inputs; };

          # Only the overlay's attribute names matter; the values come from
          # `pkgs`, which already has it applied. Fed `pkgs` as both arguments so
          # the enumeration keeps working if the overlay ever consults
          # `final`/`prev` at its top level.
          overlayPackages = builtins.intersectAttrs (import ./overlays/packages.nix {
            inherit self;
          } pkgs pkgs) pkgs;

          # Bound here rather than inline below so the pinned-packages check can
          # walk the same set without going through `self`.
          packages = {
            inherit (lazyvims) lazyvim lazyvim-light lazyvim-nightly;
            inherit (pkgs)
              beancount-language-server # from aldur/beancount-language-server
              nomicfoundation-solidity-language-server
              claude-log
              claude-skills # consumed by modules/home/claude-code.nix
              shrink-pdf
              solidity-docset
              remarks
              flatten-pdf
              watermark-pdf
              flake-lock-cooldown
              aldurs-dotfiles-version
              llmcat
              taskmd
              pi # pi-coding-agent bundled with plugins
              pi-rust # Rust port of pi, same wrapper affordances
              ;
            llm = pkgs.llmWithPlugins;
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
            inherit (pkgs) uvc-util c920-defaults;
          }
          // pkgs.lib.optionalAttrs (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) {
            inherit (pkgs) llm-mlx;
            mlx = pkgs.python3.pkgs.mlx;
          }
          // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            inherit (pkgs) faraday;
          };
        in
        {
          inherit packages;

          # Legacy packages are not automatically flake-checked
          legacyPackages = {
            inherit qemu-vm;

            # Every package here that fetches a pinned source, with the
            # `passthru.updatePin` it carries. Merged across systems into the
            # top-level `updatePins` output that CI reads.
            discoveredPins = import ./utils/discover-pins.nix { inherit (pkgs) lib; } {
              inherit self packages overlayPackages;
              inherit (pkgs.stdenv) hostPlatform;
            };
          };

          checks = import ./checks {
            inherit
              pkgs
              self
              inputs
              packages
              overlayPackages
              ;
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
      )
    )
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
        apple-container = {
          path = ./base_hosts/apple-container;
          description = "A NixOS OCI image to run in Apple `container`";
        };
      };

      utils.github-keys = import ./utils/github-keys.nix { };

      overlays = {
        mlx = import ./overlays/mlx.nix { nixpkgs = nixpkgs-darwin; };
      };

      # The CI bump matrix, derived from the `passthru.updatePin` each pinned
      # package carries — see .github/workflows/update-pinned-packages.yml.
      # Read with `nix eval --json .#updatePins`.
      updatePins =
        let
          runners = {
            linux = "ubuntu-24.04";
            darwin = "macos-26";
          };
        in
        import ./utils/update-pin-legs.nix { inherit (nixpkgs) lib; } {
          inherit runners;
          linux = self.legacyPackages.x86_64-linux.discoveredPins;
          darwin = self.legacyPackages.aarch64-darwin.discoveredPins;
        };

      lib = {
        programs = {
          git = import ./modules/shared/programs/git.nix;
          tmux = import ./modules/shared/programs/tmux.nix;
        };

        mkMlxOverlay =
          args:
          import ./overlays/mlx.nix (
            {
              nixpkgs = nixpkgs-darwin;
              # To override Python version and wheel hash:
              #     wheelPythonVersion = "3.14";
              #     wheelHash = "sha256-…"; # the matching cp314 mlx wheel on PyPI
            }
            // args
          );

        overrideUntilUpgrade = import ./utils/override-until-upgrade.nix;

        # Build `specialArgs` for a descendant flake (e.g. those in
        # `base_hosts`): merge its own inputs with this flake's, the latter
        # winning so `self` resolves to aldur-dotfiles. Encodes the merge
        # order once so consumers can't get it backwards.
        mkSpecialArgs = hostInputs: {
          inputs = hostInputs // inputs;
        };
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
