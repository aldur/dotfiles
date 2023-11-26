{
  description = "Aldur's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let
      system = "aarch64-linux";

      pkgs = import nixpkgs {
        inherit system;
      };

      systemPackages = with pkgs; [
        git
        wget

        fish
        neovim

        gnumake
        gnupg
        git-crypt
        coreutils

        ripgrep
        jq
        fzf

        htop

        python3
        poetry

        pandoc
        syncthing

        # LSPs
        rnix-lsp
        marksman

        black
        vim-vint
        yamllint
        yamlfix
        # timefhuman
        # python-lsp-server[all]
        # pyflakes
      ];

      specialArgs = {
        inherit system pkgs systemPackages;
      };
    in
    {
      nixosConfigurations = {
        # nixos-rebuild switch --flake .#nixos
        "nixos" = nixpkgs.lib.nixosSystem {
          system = specialArgs.system;
          specialArgs = specialArgs;
          modules = [
            ./configuration.nix
          ];
        };
      };
    };
}
