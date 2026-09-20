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
  nixIndexPackages = import inputs.nix-index-database { inherit pkgs; };
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
      # Command lookup only needs the small /bin index, also used by comma.
      programs.nix-index.package = nixIndexPackages.nix-index-with-small-db;
      programs.nix-index-database.comma.enable = true;

      # The upstream cache link otherwise retains the full database even
      # when nix-locate itself uses the small one.
      home.file."${config.xdg.cacheHome}/nix-index/files" =
        mkIf config.programs.nix-index.symlinkToCacheHome
          { source = lib.mkForce nixIndexPackages.nix-index-small-database; };

      home.packages = with pkgs; [
        nix-doc
        nix-search
      ];
    })
  ];
}
