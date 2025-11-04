{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
with lib;
let
  name = "better-nix-search";
  cfg = config.programs.${name};
in
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];
  options.programs.${name} = {
    enable = mkEnableOption "Better Nix search";
  };

  config = mkIf cfg.enable {
    programs.nix-index.enable = true;
    programs.nix-index-database.comma.enable = true;

    home.packages = with pkgs; [
      nix-doc
      nix-search
    ];
  };
}
