{ config, pkgs, lib, ... }:
let configDocs = config.aldur.docs;
in {
  options.aldur.docs = { enable = lib.mkEnableOption "docs"; };

  config = {
    environment.systemPackages = lib.optionals configDocs.enable
      (with pkgs; [ man-pages man-pages-posix ]);

    documentation = lib.mkIf configDocs.enable {
      enable = true;
      dev.enable = true;
      doc.enable = true;
      info.enable = true;
      nixos.enable = true;

      man = {
        enable = true;
        generateCaches = false;
        man-db.enable = false;
        mandoc.enable = true;
      };
    };
  };
}
