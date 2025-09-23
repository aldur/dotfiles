{ inputs, pkgs }:
(
  final: prev:
  let
    lazyvim = (prev.callPackage ../../nix/packages/lazyvim/lazyvim.nix { inherit inputs pkgs; });
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
          sandbox-exec -f ${../sandboxes/lazyvim.sb} ${name} "$@"
        '';
      }
    );
  }
)
