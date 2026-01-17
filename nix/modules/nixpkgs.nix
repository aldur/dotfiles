{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:
with lib;
{
  options.nixpkgs = {
    allowUnfreeByName = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "Allowed unfree to install";
    };
  };

  config = {
    nixpkgs = {
      overlays = (import ../overlays { self = inputs.self; }) ++ [
        inputs.dashp.overlays.default
      ];

      config.allowUnfreePredicate =
        pkg: builtins.elem (pkgs.lib.getName pkg) config.nixpkgs.allowUnfreeByName;
    };

    # This allows accessing pkgsUnstable anywere in the configuration.
    # https://discourse.nixos.org/t/mixing-stable-and-unstable-packages-on-flake-based-nixos-system/50351/4
    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (config.nixpkgs) config;
    };
  };
}
