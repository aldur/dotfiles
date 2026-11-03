{
  configuration,
  directory,
  inputs,
  name,
  pkgs,
  specialArgs,
}:
let
  baguetteProbe = import (directory + /tests/baguette-boot.nix) { inherit (configuration) pkgs; };
in
{
  baguette-boot = inputs.nixos-crostini.lib.mkBaguetteSmokeTest (
    baguetteProbe
    // {
      inherit configuration;
      name = "${name}-baguette-smoke";
      probeFiles = (baguetteProbe.probeFiles or { }) // {
        "appliance-state.sh" = "${./state.sh}";
      };
      extraProbe =
        builtins.readFile ./isolation.sh + builtins.readFile ./baguette.sh + baguetteProbe.extraProbe;
    }
  );
  qemu-boot = import (directory + /tests/qemu-boot.nix) {
    inherit pkgs specialArgs;
  };
}
