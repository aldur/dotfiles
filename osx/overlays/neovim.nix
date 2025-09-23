(
  final: prev:
  let
    neovim = (prev.callPackage ../../neovim/neovim.nix { });
    # neovim = (
    #   prev.callPackage ../neovim/neovim.nix {
    #     nvim-package = neovim-nightly-overlay.packages.${pkgs.system}.default;
    #   }
    # );
  in
  {
    neovim = (
      prev.writeShellApplication {
        name = "nvim";

        runtimeInputs = [
          neovim
        ];

        # Jail nvim
        text = ''
          sandbox-exec -f ${../sandboxes/neovim.sb} nvim "$@"
        '';
      }
    );
  }
)
