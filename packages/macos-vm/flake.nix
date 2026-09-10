{
  description = "Private dependencies and guest builder for the macOS VM launcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = dependencies: {
    # Receive the parent's inputs explicitly, without a circular flake input.
    # Preserve its self so modules and dotfiles use the current checkout.
    lib.mkGuestSystem =
      inputs:
      (dependencies.nix-darwin.lib.darwinSystem {
        specialArgs.inputs = inputs // {
          inherit (dependencies) nix-darwin nix-homebrew nix-rosetta-builder;
        };
        modules = [
          "${inputs.self}/modules/darwin/configuration.nix"
          "${inputs.self}/base_hosts/macos/macos.nix"
          "${inputs.self}/base_hosts/macos/vm.nix"
        ];
      }).system;
  };
}
