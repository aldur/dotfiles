{
  description = "An offline Pi sandbox for Apple container, with inference on macOS.";

  inputs.aldur-dotfiles.url = "github:aldur/dotfiles";

  outputs =
    { aldur-dotfiles, ... }:
    let
      inherit (aldur-dotfiles.inputs) flake-utils home-manager;
      # Get the parent and the packages from one dotfiles revision.
      apple-container = (import "${aldur-dotfiles}/base_hosts/apple-container/flake.nix").outputs {
        inherit aldur-dotfiles;
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        targetSystem = apple-container.lib.linuxSystem system;
        base = apple-container.lib.mkConfiguration targetSystem;
        image = import ./image.nix {
          inherit (base) pkgs;
          inherit home-manager;
          inherit (base.config.virtualisation.appleContainer) uid;
          inherit (base._module.args) mkOciArchive;
          baseHome = base.config.home-manager.users.${base.config.mainUser};
          lazyvim-light = aldur-dotfiles.packages.${targetSystem}.lazyvim-light;
          dotfiles = aldur-dotfiles;
        };
      in
      {
        packages = rec {
          container-image = image.image;
          default = container-image;
        };

        checks.image = import ./tests {
          inherit (base) pkgs;
          inherit image;
          dotfiles = aldur-dotfiles;
        };
        checks.hardening = import ./tests/hardening.nix {
          inherit (base) pkgs;
          inherit image;
        };
      }
    );
}
