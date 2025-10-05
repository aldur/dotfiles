{ pkgs, lib, ... }:
with lib;
let configDocs = config.aldur.docs;
in {

  options.aldur.docs = { enable = mkEnableOption "docs"; };

  config = optionals configDocs.enable {
    environment.systemPackages = with pkgs; [ man-pages man-pages-posix ];

    documentation = {
      dev.enable = true;
      man.enable = true;
      doc.enable = true;
      info.enable = true;
      enable = true;
      nixos.enable = true;

      man.generateCaches = false;
    };
  };
}
