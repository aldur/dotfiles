{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
      inputs.home-manager.follows = "home-manager";
      inputs.systems.follows = "systems";
    };

    nixCats.url = "github:BirdeeHub/nixCats-nvim";
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "";
      inputs.flake-compat.follows = "";
      inputs.treefmt-nix.follows = "";
      inputs.hercules-ci-effects.follows = "";
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
  };
  outputs = { self, flake-utils, nixpkgs, ... }@inputs:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nixCatsLazyVim =
          (pkgs.callPackage ./packages/lazyvim/lazyvim.nix { inherit inputs; });
        defaultPackage = nixCatsLazyVim.defaultPackage;
      in { packages = inputs.nixCats.utils.mkAllWithDefault defaultPackage; }))
    // {

      templates = {
        vm-nogui = {
          path = ./base_hosts/qemu;
          description = "A QEMU VM";
        };
        lxc-nixos = {
          path = ./base_hosts/lxc-nixos;
          description = "An lxc-nixos container to run in ChromeOS Crostini";
        };
      };

      # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/nixos-flake-and-module-system
      specialArgs =
        # This ugly thing ensures that, when descendant flakes (e.g. those in `base_hosts`)
        # will use this flake, all (this flake) inputs will be correctly passed
        # as arguments to the modules.
        let thisFlakeInputs = inputs // { inherit self; };
        in { inputs = thisFlakeInputs; };

      nixosModules.default = ./modules/nixos/configuration.nix;
      darwinModules.default = ./modules/darwin/configuration.nix;
    };
}
