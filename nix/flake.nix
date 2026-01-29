{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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

    nvim-treesitter-main = {
      url = "github:iofq/nvim-treesitter-main";
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
        # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2505";
        nixpkgs.follows = "nixpkgs";

        nixpkgs-regression.follows = "";
        nixpkgs-23-11.follows = "";
        flake-parts.follows = "";
        git-hooks-nix.follows = "";
      };

    };
  };
  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      ...
    }@inputs:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = import ./overlays { inherit self; };
        };
        lazyvims = pkgs.callPackage ./packages/lazyvim/lazyvim.nix { inherit inputs; };
        qemu-vm = pkgs.callPackage ./packages/qemu-vm/qemu-vm.nix { inherit inputs; };
      in
      {
        packages = {
          inherit (lazyvims) lazyvim lazyvim-light;
          inherit (pkgs)
            beancount-language-server # from aldur/beancount-language-server
            nomicfoundation-solidity-language-server
            shrinkpdf
            solidity-docset
            remarks
            flatten-pdf
            flake-lock-cooldown
            ;
          llm = pkgs.llmWithPlugins;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          inherit (pkgs) uvc-util c920-defaults;
        };

        # Legacy packages are not automatically flake-checked
        legacyPackages = {
          inherit qemu-vm;
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
      specialArgs =
        # This ugly thing ensures that, when descendant flakes (e.g. those in `base_hosts`)
        # will use this flake, all (this flake) inputs will be correctly passed
        # as arguments to the modules.
        let
          thisFlakeInputs = inputs // {
            inherit self;
          };
        in
        {
          inputs = thisFlakeInputs;
        };

      utils.github-keys = import ./utils/github-keys.nix { };

      nixosModules = {
        default = ./modules/nixos/configuration.nix;
        audit = ./modules/nixos/audit.nix;
        docker = ./modules/nixos/docker.nix;
      };

      darwinModules.default = ./modules/darwin/configuration.nix;
    };
}
