{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  name = "better-nix-search";
  cfg = config.programs.${name};
in
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];
  options.programs.${name} = {
    enable = mkEnableOption "Better Nix search";
  };

  config = lib.mkMerge [
    {
      # Override defaults inherited by importing the nix-index-database module.
      programs.nix-index.enable = cfg.enable;
      programs.nix-index.symlinkToCacheHome = lib.mkDefault cfg.enable;
    }

    (mkIf cfg.enable {
      programs.nix-index-database.comma.enable = true;

      home.packages = with pkgs; [
        nix-doc
        nix-search
      ];
    })
  ];
}
