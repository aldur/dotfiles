{
  description = "LazyVim in `nix`";

  inputs = { aldur-dotfiles = { url = "git+file://../../../..?dir=nix"; }; };

  outputs = { aldur-dotfiles, ... }:
    let
      inherit (aldur-dotfiles.inputs.nixCats) utils;
      nixpkgs = aldur-dotfiles.inputs.nixpkgs;
      forEachSystem = utils.eachSystem nixpkgs.lib.platforms.all;
    in forEachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        nixCatsLazyVim =
          (pkgs.callPackage ./lazyvim.nix { inherit (aldur-dotfiles) inputs; });
        defaultPackage = nixCatsLazyVim.defaultPackage;
        overlays = nixCatsLazyVim.overlays;
      in {
        inherit overlays;
        packages = utils.mkAllWithDefault defaultPackage;
      });
}
