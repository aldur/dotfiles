{ inputs, pkgs }:
(
  final: prev:
  let
    lazyvim = (prev.callPackage ../../packages/lazyvim/lazyvim.nix { inherit inputs pkgs; });
    name = "lazyvim";
  in
  {
    lazyvim = (
      prev.writeShellApplication {
        inherit name;

        runtimeInputs = [
          lazyvim.defaultPackage
        ];

        # Jail nvim
        text = ''
          sandbox-exec -f ${../../../osx/sandboxes/lazyvim.sb} ${name} "$@"
        '';
      }
    );
  }
)
