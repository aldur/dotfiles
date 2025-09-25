{
  pkgs,
  lib,
  ...
}:
with lib;
let
  basePackages = with pkgs; [
    dashp
    dasht
  ];

  dashDocsetsDir = ".local/share/dasht/docsets/.keep";

  download-nix-docsets = pkgs.writeShellApplication {
    name = "download-nix-docsets";
    runtimeInputs = [
      curl
      gnutar
    ];
    text = ''
      curl https://aldur.github.io/nixpkgs.docset/all.tgz | tar --overwrite -xzf - -C "$DASHT_DOCSETS_DIR"
    '';
  };
in
{
  environment.systemPackages = basePackages;

  home-manager.users.aldur =
    { ... }:
    {
      home.file.${dashDocsetsDir} = (pkgs.writeText "");
      home.sessionVariables = {
        DASHT_DOCSETS_DIR = "~/${dashDocsetsDir}";
      };
      home.packages = [ download-nix-docsets ];
    };
}
