{
  description = "aldur's nvim configuration";

  inputs = { aldur-dotfiles = { url = "git+file://../../../..?dir=nix"; }; };

  outputs = { aldur-dotfiles, ... }:
    aldur-dotfiles.inputs.flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import aldur-dotfiles.inputs.nixpkgs { inherit system; };
      in {
        packages = rec {
          neovim-nightly = pkgs.callPackage ./neovim.nix {
            nvim-package =
              aldur-dotfiles.inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
          };
          neovim = pkgs.callPackage ./neovim.nix { };
          default = neovim;
        };
      });
}
