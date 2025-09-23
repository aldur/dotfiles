{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  name = "better-nix-search";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "Better Nix search";
  };

  config = mkIf cfg.enable {
    programs.nix-index.enable = true;
    programs.nix-index-database.comma.enable = true;

    environment.systemPackages = with pkgs; [
      nix-doc
      nix-search
    ];

  };
}
