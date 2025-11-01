(
  final: prev:
  let
    neovim = (prev.callPackage ../../packages/nvim/neovim.nix { });
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
          sandbox-exec -f ${../../../osx/sandboxes/neovim.sb} nvim "$@"
        '';
      }
    );
  }
)
