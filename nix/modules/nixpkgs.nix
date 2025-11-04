{ lib, inputs, ... }:
with lib;
{
  options.nixpkgs = {
    allowUnfreeByName = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Allowed unfree to install";
    };
  };

  config.nixpkgs = {
    overlays = (import ../overlays) ++ [
      inputs.dashp.overlays.default
    ];

    config.allowUnfreePredicate =
      pkg: builtins.elem (pkgs.lib.getName pkg) config.nixpkgs.allowUnfreeByName;
  };

}
